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
# Argument parsing.
#
# cf. https://sookocheff.com/post/bash/parsing-bash-script-arguments-with-shopts/
################################################################################

alpine_ver="3.14"
container="alpine-ghc"
image="alpine-ghc"
ghc_version="8.10.7"

# NOTE: The logic associated with this will have to change for GHC 9.x and up to
# support the changes introduced with the switch to `ghc-bignum`.
numeric="gmp"

usage="USAGE: $0
    -h            show this help text
    -a ALPINE_VER override the default Alpine version
                  default: ${alpine_ver}
    -c CONTAINER  override the default container name
                  default: ${container}
    -g GHC_VER    override the version of GHC to be compiled
                  default: ${ghc_version}
    -i IMAGE      override the default image base name
                  default: ${image}
    -n NUMERIC    override the numeric library GHC is built against; either 'gmp' or 'native'
                  default: ${numeric}"

while getopts "a:c:g:i:n:h" opt; do
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
          if [ "${OPTARG}" = "gmp" ] || [ "${OPTARG}" = "native" ]; then
            numeric="${OPTARG}"
          else
            echo "Invalid NUMERIC argument (i.e. '-n')." >&2
            echo "Expected either 'gmp' or 'native', got '${OPTARG}'" >&2
            exit 1
          fi;
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

# Create the container that will be used to compile GHC from source.
buildah \
    --signature-policy=./policy.json \
    --name "${container}" \
    from --pull "docker.io/library/alpine:${alpine_ver}"

################################################################################
# Copy `ghcup` from another container.
################################################################################

buildah unshare ./common/copy_ghcup.sh "ghcup" "${container}"

################################################################################
# Dependencies.
################################################################################

buildah run "${container}" \
    apk add --no-cache \
        autoconf \
        automake \
        binutils-gold \
        build-base \
        curl \
        coreutils \
        cpio \
        ghc \
        git \
        linux-headers \
        libffi-dev \
        musl-dev \
        ncurses-dev \
        perl \
        python3 \
        py3-sphinx \
        zlib-dev \
        xz

# Copy the appropriate build file, depending on the chosen numeric library.
if [ "${numeric}" = "gmp" ]; then
  buildah copy --chmod 444 "${container}" \
      ./ghc/build-gmp.mk \
      /tmp/build.mk
elif [ "${numeric}" = "native" ]; then
  # TODO: Add a check for GHC version > 9.x; in that case we need to use a
  # `ghc-bignum` flag w/ `native` instead of the old flag for `simple`.
  buildah copy --chmod 444 "${container}" \
      ./ghc/build-simple.mk \
      /tmp/build.mk
else # Should be impossible...
    echo "This code path should be unreachable!" >&2
    echo "Invalid NUMERIC argument (i.e. '-n')" >&2
    echo "Expected either 'gmp' or 'native', got '${numeric}'" >&2
    exit 1
fi;

# Copy all patches that will be applied to the GHC source tree.
buildah copy --chmod 444 "${container}" \
    ./ghc/patches \
    /tmp/patches

# Copy wrapper script that will invoke `ghcup` to compile GHC.
buildah copy --chmod 111 "${container}" \
    ./ghc/compile_ghc.sh \
    /tmp/compile_ghc.sh

################################################################################
# Compile GHC.
################################################################################

# Compile GHC.
buildah run "${container}" \
    ./tmp/compile_ghc.sh "${ghc_version}"

# Uninstall the bootstrapping compiler.
buildah run "${container}" \
    apk del ghc

# Clean up the build files, build scripts, and patches.
buildah run "${container}" \
    rm -rf "/tmp/{build.mk,compile_ghc.sh,patches}"

# Add `ghcup`'s bin directory to the container's `PATH`.
#
# NOTE: This little bit of indirection is needed to get the container's 'PATH',
# since '$PATH' would be sourced from the host.
cntr_path=$(buildah run "${container}" printenv PATH)
buildah config \
  --env PATH="${cntr_path}:/root/.ghcup/bin" \
  "${container}"

################################################################################
# Generate the final image.
################################################################################

# NOTE: `buildah` uses `/var/tmp` (or $TMPDIR) as a staging area when assembling
# images.
#
# On systems where `/var/tmp` is mounted as `tmpfs`, this can cause `buildah` to
# run out of space.
mkdir -p ./tmp
TMPDIR=./tmp \
  image_id=$(
    buildah \
      --signature-policy=./policy.json \
      commit --rm "${container}" "${image}:${ghc_version}"
  )
rm -rf ./tmp
echo "${image_id}"
