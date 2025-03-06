FROM --platform=linux/amd64 ubuntu:22.04 AS napari
# if you change the Ubuntu version, remember to update
# the APT definitions for Xpra below so it reflects the
# new codename (e.g. 20.04 was focal, 22.04 had jammy)

# below env var required to install libglib2.0-0 non-interactively
ENV TZ=America/Los_Angeles
ARG DEBIAN_FRONTEND=noninteractive
ARG NAPARI_COMMIT=main

# install python resources + graphical libraries used by qt and vispy
RUN apt-get update && \
    apt-get install -qqy  \
        build-essential \
        python3.9 \
        python3-pip \
        git \
        mesa-utils \
        x11-utils \
        libegl1-mesa \
        libopengl0 \
        libgl1-mesa-glx \
        libglib2.0-0 \
        libfontconfig1 \
        libxrender1 \
        libdbus-1-3 \
        libxkbcommon-x11-0 \
        libxi6 \
        libxcb-icccm4 \
        libxcb-image0 \
        libxcb-keysyms1 \
        libxcb-randr0 \
        libxcb-render-util0 \
        libxcb-xinerama0 \
        libxcb-xinput0 \
        libxcb-xfixes0 \
        libxcb-shape0 \
        && apt-get clean

ARG MINIFORGE_NAME=Miniforge3
ARG MINIFORGE_VERSION=24.11.3-0
ARG TARGETPLATFORM

ENV CONDA_DIR=/opt/conda
ENV LANG=C.UTF-8 LC_ALL=C.UTF-8
ENV PATH=${CONDA_DIR}/bin:${PATH}

# 1. Install just enough for conda to work
# 2. Keep $HOME clean (no .wget-hsts file), since HSTS isn't useful in this context
# 3. Install miniforge from GitHub releases
# 4. Apply some cleanup tips from https://jcrist.github.io/conda-docker-tips.html
#    Particularly, we remove pyc and a files. The default install has no js, we can skip that
# 5. Activate base by default when running as any *non-root* user as well
#    Good security practice requires running most workloads as non-root
#    This makes sure any non-root users created also have base activated
#    for their interactive shells.
# 6. Activate base by default when running as root as well
#    The root user is already created, so won't pick up changes to /etc/skel
RUN apt-get update > /dev/null && \
    apt-get install --no-install-recommends --yes \
        wget bzip2 ca-certificates \
        git \
        tini \
        > /dev/null && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* && \
    wget --no-hsts --quiet https://github.com/conda-forge/miniforge/releases/download/${MINIFORGE_VERSION}/${MINIFORGE_NAME}-${MINIFORGE_VERSION}-Linux-$(uname -m).sh -O /tmp/miniforge.sh && \
    /bin/bash /tmp/miniforge.sh -b -p ${CONDA_DIR} && \
    rm /tmp/miniforge.sh && \
    conda clean --tarballs --index-cache --packages --yes && \
    find ${CONDA_DIR} -follow -type f -name '*.a' -delete && \
    find ${CONDA_DIR} -follow -type f -name '*.pyc' -delete && \
    conda clean --force-pkgs-dirs --all --yes  && \
    echo ". ${CONDA_DIR}/etc/profile.d/conda.sh && conda activate base" >> /etc/skel/.bashrc && \
    echo ". ${CONDA_DIR}/etc/profile.d/conda.sh && conda activate base" >> ~/.bashrc
    #if [ ${MINIFORGE_NAME} = "Mambaforge"* ]; then \
    #    echo '. ${CONDA_DIR}/etc/.mambaforge_deprecation.sh' >> /etc/skel/.bashrc && \
    #    echo '. ${CONDA_DIR}/etc/.mambaforge_deprecation.sh' >> ~/.bashrc; \
    #fi

#COPY ubuntu/mambaforge_deprecation.sh ${CONDA_DIR}/etc/.mambaforge_deprecation.sh

# create environment for napari
RUN conda create -n naparienv python=3.11
# install napari from repo
# see https://github.com/pypa/pip/issues/6548#issuecomment-498615461 for syntax
RUN conda init bash && \
    . ~/.bashrc && \
    conda activate naparienv && \
    pip install --upgrade pip && \
    pip install "napari[all]==0.5.6"
    #"napari[all] @ git+https://github.com/napari/napari.git@${NAPARI_COMMIT}"

# copy examples
COPY examples /tmp/examples

ENTRYPOINT ["python3", "-m", "napari"]

#########################################################
# Extend napari with a preconfigured Xpra server target #
#########################################################

FROM napari AS napari-xpra

ARG DEBIAN_FRONTEND=noninteractive

# Install Xpra and dependencies
RUN apt-get update && apt-get install -y wget gnupg2 apt-transport-https \
    software-properties-common ca-certificates && \
    wget -O "/usr/share/keyrings/xpra.asc" https://xpra.org/xpra.asc && \
    wget -O "/etc/apt/sources.list.d/xpra.sources" https://raw.githubusercontent.com/Xpra-org/xpra/master/packaging/repos/jammy/xpra.sources


RUN apt-get update && \
    apt-get install -yqq \
        xpra \
        xvfb \
        xterm \
        sshfs && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Desktop
RUN apt-get update && \
    apt-get install -yqq \
        xfce4 \
        xfce4-terminal


ENV DISPLAY=:100
ENV XPRA_PORT=9876
ENV XPRA_START="python3 -m napari"
ENV XPRA_EXIT_WITH_CLIENT="yes"
ENV XPRA_XVFB_SCREEN="1920x1080x24+32"
EXPOSE 9876

CMD echo "Launching napari on Xpra. Connect via http://localhost:$XPRA_PORT or $(hostname -i):$XPRA_PORT"; \
    xpra start \
    --start-child=startxfce4 \
    --bind-tcp=0.0.0.0:$XPRA_PORT \
    --html=on \
    --exit-with-client="$XPRA_EXIT_WITH_CLIENT" \
    --daemon=no \
    --xvfb="/usr/bin/Xvfb +extension Composite -screen 0 $XPRA_XVFB_SCREEN -nolisten tcp -noreset" \
    --pulseaudio=no \
    --notifications=no \
    --bell=no \
    $DISPLAY

ENTRYPOINT []