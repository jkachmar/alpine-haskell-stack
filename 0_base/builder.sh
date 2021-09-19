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

container="base"
image="base"
# NOTE: The logic associated with this will have to change for GHC 9.x and up to
# support the changes introduced with the switch to `ghc-bignum`.
numeric="gmp"

usage="USAGE: $0
    -h           show this help text
    -c CONTAINER override the default container name
                 default: ${container}
    -i IMAGE     override the default image name
                 default: ${image}
    -n NUMERIC   override the numeric library GHC is built against; either 'gmp' or 'simple'
                 default: ${numeric}"

while getopts "c:i:n:h" opt; do
  case ${opt} in
    c ) {
          container="${OPTARG}"
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

# Add the numeric library to container and image names.
container="${container}-${numeric}"
image="${image}-${numeric}"

################################################################################
# Container and basic dependencies.
################################################################################

# Create the "base" container that will be used elsewhere in the project.
#
# NOTE: Alternatively: `buildah commit --rm` (at the end of the script) removes
# the working container.
#
# XXX: Reusing the container by name if it exists seems like not the best idea
# but it's convenient for development.
buildah \
    --signature-policy=./policy.json \
    --name "${container}" \
    from --pull docker.io/library/alpine:3.14 \
    || true

# Update index files and upgrade the currently installed packages.
#
# NOTE: This breaks reproducibility.
buildah run "${container}" \
    apk -U upgrade

# Install basic dependencies required by 'ghcup', 'stack', and 'cabal-install'.
buildah run "${container}" \
    apk add \
      curl \
      gcc \
      git \
      libc-dev \
      xz

if [ "${numeric}" = "gmp" ]; then
  echo "Installing 'libgmp'."
  buildah run "${container}" \
      apk add gmp-dev
fi;

################################################################################
# Download and install `ghcup`.
################################################################################

ghcup_version="0.1.16.2"
ghcup_expected_checksum="d5e43b95ce1d42263376e414f7eb7c5dd440271c7c6cd9bad446fdeff3823893"

# Fetch `ghcup`.
buildah run "${container}" \
    wget \
        -O "/tmp/ghcup-${ghcup_version}" \
        "https://downloads.haskell.org/~ghcup/${ghcup_version}/x86_64-linux-ghcup-${ghcup_version}"

# Copy the checksum validation script into the container...
buildah copy --chmod 111 "${container}" \
    ./0_base/validate_checksum.sh \
    /tmp/validate_checksum.sh

# ...and verify that the expected and actual actual `ghcup` checksums match.
buildah run "${container}" \
    ./tmp/validate_checksum.sh \
        "/tmp/ghcup-${ghcup_version}" \
        "${ghcup_expected_checksum}"

# Relocate `ghcup`...
buildah run "${container}" \
    mv /tmp/"ghcup-${ghcup_version}" /usr/bin/ghcup

# ...set it to be executable...
buildah run "${container}" \
    chmod +x /usr/bin/ghcup

# ...clean up any scripts.
buildah run "${container}" \
    rm -rf /tmp/validate_checksum.sh

################################################################################
# Generate the final image.
################################################################################

buildah \
    --signature-policy=./policy.json \
    commit "${container}" "${image}"
