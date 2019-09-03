################################################################################
# Set up environment variables, OS packages, and scripts that are common to the
# build and distribution layers in this Dockerfile
FROM alpine:3.9 AS base

# Must be one of 'gmp' or 'simple'; used to build GHC with support for either
# 'integer-gmp' (with 'libgmp') or 'integer-simple'
#
# Default to building with 'integer-gmp' and 'libgmp' support
ARG GHC_BUILD_TYPE

# Must be a valid GHC version number, only tested with 8.4.4, 8.6.4, and 8.6.5
#
# Default to GHC version 8.6.5 (latest at the time of writing)
ARG GHC_VERSION=8.6.5

# Add ghcup's bin directory to the PATH so that the versions of GHC it builds
# are available in the build layers
ENV GHCUP_INSTALL_BASE_PREFIX=/
ENV PATH=/.ghcup/bin:$PATH

# Use the latest version of ghcup (at the time of writing)
ENV GHCUP_VERSION=0.0.7
ENV GHCUP_SHA256="b4b200d896eb45b56c89d0cfadfcf544a24759a6ffac029982821cc96b2faedb  ghcup"

# Install the basic required dependencies to run 'ghcup' and 'stack'
RUN apk upgrade --no-cache &&\
    apk add --no-cache \
        curl \
        gcc \
        git \
        libc-dev \
        xz &&\
    if [ "${GHC_BUILD_TYPE}" = "gmp" ]; then \
        echo "Installing 'libgmp'" &&\
        apk add --no-cache gmp-dev; \
    fi

# Download, verify, and install ghcup
RUN echo "Downloading and installing ghcup" &&\
    cd /tmp &&\
    wget -P /tmp/ "https://gitlab.haskell.org/haskell/ghcup/raw/${GHCUP_VERSION}/ghcup" &&\
    if ! echo -n "${GHCUP_SHA256}" | sha256sum -c -; then \
        echo "ghcup-${GHCUP_VERSION} checksum failed" >&2 &&\
        exit 1 ;\
    fi ;\
    mv /tmp/ghcup /usr/bin/ghcup &&\
    chmod +x /usr/bin/ghcup

################################################################################
# Intermediate layer that builds GHC
FROM base AS build-ghc

# Carry build args through to this stage
ARG GHC_BUILD_TYPE=gmp
ARG GHC_VERSION=8.6.5

RUN echo "Install OS packages necessary to build GHC" &&\
    apk add --no-cache \
        autoconf \
        automake \
        binutils-gold \
        build-base \
        coreutils \
        cpio \
        ghc \
        linux-headers \
        libffi-dev \
        llvm5 \
        musl-dev \
        ncurses-dev \
        perl \
        python3 \
        py3-sphinx \
        zlib-dev

COPY docker/build-gmp.mk /tmp/build-gmp.mk
COPY docker/build-simple.mk /tmp/build-simple.mk
RUN if [ "${GHC_BUILD_TYPE}" = "gmp" ]; then \
        echo "Using 'integer-gmp' build config" &&\
        apk add --no-cache gmp-dev &&\
        mv /tmp/build-gmp.mk /tmp/build.mk && rm /tmp/build-simple.mk; \
    elif [ "${GHC_BUILD_TYPE}" = "simple" ]; then \
        echo "Using 'integer-simple' build config" &&\
        mv /tmp/build-simple.mk /tmp/build.mk && rm tmp/build-gmp.mk; \
    else \
        echo "Invalid argument \[ GHC_BUILD_TYPE=${GHC_BUILD_TYPE} \]" && exit 1; \
fi

RUN echo "Compiling and installing GHC" &&\
    LD=ld.gold \
    SPHINXBUILD=/usr/bin/sphinx-build-3 \
      ghcup -v compile -j $(nproc) -c /tmp/build.mk ${GHC_VERSION} ghc-8.4.3 &&\
    rm /tmp/build.mk &&\
    echo "Uninstalling GHC bootstrapping compiler" &&\
    apk del ghc &&\
    ghcup set ${GHC_VERSION}

################################################################################
# Intermediate layer that assembles 'stack' tooling
FROM base AS build-tooling

ENV STACK_VERSION=2.1.3
ENV STACK_SHA256="4e937a6ad7b5e352c5bd03aef29a753e9c4ca7e8ccc22deb5cd54019a8cf130c  stack-${STACK_VERSION}-linux-x86_64-static.tar.gz"

# Download, verify, and install stack
RUN echo "Downloading and installing stack" &&\
    cd /tmp &&\
    wget -P /tmp/ "https://github.com/commercialhaskell/stack/releases/download/v${STACK_VERSION}/stack-${STACK_VERSION}-linux-x86_64-static.tar.gz" &&\
    if ! echo -n "${STACK_SHA256}" | sha256sum -c -; then \
        echo "stack-${STACK_VERSION} checksum failed" >&2 &&\
        exit 1 ;\
    fi ;\
    tar -xvzf /tmp/stack-${STACK_VERSION}-linux-x86_64-static.tar.gz &&\
    cp -L /tmp/stack-${STACK_VERSION}-linux-x86_64-static/stack /usr/bin/stack &&\
    rm /tmp/stack-${STACK_VERSION}-linux-x86_64-static.tar.gz &&\
    rm -rf /tmp/stack-${STACK_VERSION}-linux-x86_64-static

################################################################################
# Assemble the final image
FROM base

# Carry build args through to this stage
ARG GHC_BUILD_TYPE=gmp
ARG GHC_VERSION=8.6.5

COPY --from=build-ghc /.ghcup /.ghcup
COPY --from=build-tooling /usr/bin/stack /usr/bin/stack

# NOTE: 'stack --docker' needs bash + usermod/groupmod (from shadow)
RUN apk add --no-cache bash shadow

RUN ghcup set ${GHC_VERSION} &&\
    stack config set system-ghc --global true
