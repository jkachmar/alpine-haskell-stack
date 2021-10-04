#!/usr/bin/env sh
set -eu

################################################################################
# Pre-flight checks.
################################################################################

command -v git >/dev/null 2>&1 || { echo >&2 "git is not installed, aborting."; exit 1; }
command -v buildah >/dev/null 2>&1 || { echo >&2 "buildah is not installed, aborting."; exit 1; }

# Start the script in the top-level repository directory no matter what.
cd "$( git rev-parse --show-toplevel )"

################################################################################
# Argument parsing and related values.
#
# cf. https://sookocheff.com/post/bash/parsing-bash-script-arguments-with-shopts/
################################################################################

alpine_ver="3.14"
container="ghc-with-tooling"
image="ghc-with-tooling"
ghc_version="8.10.7"

# NOTE: The logic associated with this will have to change for GHC 9.x and up to
# support the changes introduced with the switch to `ghc-bignum`.
numeric="gmp"

cabal_version="3.6.0.0"

stack_version="2.7.3"
stack_expected_checksum="c5bce24defa2b2b86f1bbb14bed4f1ee83bec14c6ed9fcc81174d5473fbf3450"

hls_version="1.4.0"

usage="USAGE: $0
    -h            show this help text
    -a ALPINE_VER override the default Alpine version
                  default: ${alpine_ver}
    -c CONTAINER  override the default container name
                  default: ${container}
    -g GHC_VER    override the numeric library GHC is built against; either 'gmp' or 'simple'
                  default: ${ghc_version}
    -i IMAGE      override the default image base name
                  default: ${image}
    -n NUMERIC    override the numeric library GHC is built against; either 'gmp' or 'simple'
                  default: ${numeric}
    -C CABAL_VER  override the default version of 'cabal-install' to build
                  default: ${cabal_version}
    -S STACK_VER  override the default version of 'stack' to download and install
                  default: ${stack_version}
    -H HLS_VER    override the default version of 'haskell-language-server' to download and install
                  default: ${hls_version}"

while getopts "a:c:g:i:n:C:S:H:h" opt; do
  case ${opt} in
    a ) {
        alpine_ver="${OPTARG}"
    };;
    c ) {
        container="${OPTARG}"
    };;
    g ) {
        ghc_version="${OPTARG}"
    };;
    i ) {
        image="${OPTARG}"
    };;
    n ) {
        if [ "${OPTARG}" = "gmp" ] || [ "${OPTARG}" = "simple" ]; then
          numeric="${OPTARG}"
        else
          echo "Invalid NUMERIC argument (i.e. '-n')." >&2
          echo "Expected either 'gmp' or 'simple', got '${OPTARG}'" >&2
          exit 1
        fi;
    };;
    C ) {
        cabal_version="${OPTARG}"
    };;
    S ) {
        stack_version="${OPTARG}"
    };;
    H ) {
        hls_version="${OPTARG}"
    };;
    h ) {
          echo "${usage}"
          exit 0
    };;
    \? ) {
          echo "${usage}"
          exit 1
    };;
  esac
done
shift $((OPTIND -1))

if [ "$#" -ne 0 ]; then
  exit 1
fi

# Add the GHC version and numeric library to container and image names.
container="${container}-${numeric}-${ghc_version}"
image="${image}-${numeric}"

################################################################################
# Container.
################################################################################

# Create the container that will be used to download and/or compile various bits
# of Haskell tooling.
buildah \
    --signature-policy=./policy.json \
    --name "${container}" \
    from --pull "docker.io/library/alpine:${alpine_ver}"

# Install common dependencies.
buildah run "${container}" \
    apk add \
      binutils-gold \
      curl \
      gcc \
      musl-dev \
      ncurses-libs \
      xz \
      zlib

if [ "${numeric}" = "gmp" ]; then
    buildah run "${container}" \
        apk add gmp-dev
fi

################################################################################
# Copy `ghcup` (and files) from other containers.
################################################################################

buildah unshare ./common/copy_ghcup.sh "ghcup" "${container}"
buildah unshare ./common/copy_ghcup_bin_dir.sh "ghc-${numeric}:${ghc_version}" "${container}"

# Add `ghcup`'s bin directory to the container's `PATH`.
#
# NOTE: This little bit of indirection is needed to get the container's 'PATH',
# since '$PATH' would be sourced from the host.
cntr_path=$(buildah run "${container}" printenv PATH)
buildah config \
  --env PATH="${cntr_path}:/root/.ghcup/bin" \
  "${container}"

################################################################################
# Download and install `cabal-install.
#
# TODO: Compile `cabal-install` from source for non-gmp images so that the
# library won't be necessary at all.
#
# This should be easier once `ghcup` re-adds the `ghcup compile cabal`
# subcommand; cf. https://gitlab.haskell.org/haskell/ghcup-hs/-/issues/254
################################################################################

buildah run "${container}" \
    ghcup install cabal "${cabal_version}"

################################################################################
# Download and install `stack`.
################################################################################

# Fetch `stack`.
buildah run "${container}" \
    wget \
        -O "/tmp/stack-${stack_version}.tar.gz" \
        "https://github.com/commercialhaskell/stack/releases/download/v${stack_version}/stack-${stack_version}-linux-x86_64-static.tar.gz"

# Copy the checksum validation script into the container...
buildah copy --chmod 111 "${container}" \
    ./common/validate_checksum.sh \
    /tmp/validate_checksum.sh

# ...and verify that the expected and actual actual `stack` checksums match.
buildah run "${container}" \
    ./tmp/validate_checksum.sh \
        "/tmp/stack-${stack_version}.tar.gz" \
        "${stack_expected_checksum}"

# Extract the `stack` binary...
buildah run "${container}" \
    tar -xvzf "/tmp/stack-${stack_version}.tar.gz" \
      --directory "/tmp"

# ...relocate it...
buildah run "${container}" \
    mv "/tmp/stack-${stack_version}-linux-x86_64-static/stack" /usr/bin/stack

# ...make it executable...
buildah run "${container}" \
    chmod +x /usr/bin/stack

# ...and clean up after ourselves.
buildah run "${container}" rm "/tmp/stack-${stack_version}.tar.gz"
buildah run "${container}" rm -rf "/tmp/stack-${stack_version}-linux-x86_64-static"
buildah run "${container}" rm /tmp/validate_checksum.sh

################################################################################
# Compile the Haskell Language Server (HLS) from source.
################################################################################

# Install HLS-specific dependencies.
buildah run "${container}" \
    apk add \
      ncurses-dev \
      zlib-dev

# NOTE: This is just some arbirary time, but it's fixed here so that the package
# set chosen by `cabal-install` should be consistent.
buildah run "${container}" \
    cabal update hackage.haskell.org,2021-10-03T23:05:17Z

# Compile HLS...
buildah run "${container}" \
    ghcup compile hls \
      --version "${hls_version}" \
      --jobs "$(nproc)" \
      "${ghc_version}"

# ...and set it as the default version.
buildah run "${container}" \
    ghcup set hls "${hls_version}"

# Remove HLS-specific system dependencies...
buildah run "${container}" \
    apk del \
      ncurses-dev \
      zlib-dev

# ...and leftover `cabal-install` build cruft.
buildah run "${container}" \
    rm -rf /root/.cabal

################################################################################
# Generate the final image.
################################################################################

buildah \
    --signature-policy=./policy.json \
    commit --rm "${container}" "${image}:${ghc_version}"
