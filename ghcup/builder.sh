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
container="ghcup"
image="ghcup"

usage="USAGE: $0
    -h           show this help text
    -a ALPINE_VER override the default Alpine version
                  default: ${alpine_ver}
    -c CONTAINER override the default container name
                 default: ${container}
    -i IMAGE      override the default image name
                  default: ${image}"

while getopts "a:c:i:h" opt; do
  case ${opt} in
    a ) {
          alpine_ver="${OPTARG}"
    };;
    c ) {
          container="${OPTARG}"
    };;
    i ) {
          image="${OPTARG}"
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

################################################################################
# Container and basic dependencies.
################################################################################

buildah \
    --signature-policy=./policy.json \
    --name "${container}" \
    from --pull docker.io/library/alpine:3.14

# Update index files and upgrade the currently installed packages.
#
# NOTE: This breaks reproducibility.
buildah run "${container}" \
    apk -U upgrade

# Install basic dependencies required by 'ghcup', 'stack', and 'cabal-install'.
buildah run "${container}" \
    apk add \
      curl \
      xz

################################################################################
# Download and install `ghcup`.
################################################################################

ghcup_version="0.1.17.2"
ghcup_expected_checksum="e9adb022b9bcfe501caca39e76ae7241af0f30fbb466a2202837a7a578607daf"

# Fetch `ghcup`.
buildah run "${container}" \
    wget \
        -O "/tmp/ghcup-${ghcup_version}" \
        "https://downloads.haskell.org/~ghcup/${ghcup_version}/x86_64-linux-ghcup-${ghcup_version}"

# Copy the checksum validation script into the container...
buildah copy --chmod 111 "${container}" \
    ./ghcup/validate_checksum.sh \
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

# NOTE: Tagging the image with the `ghcup_version` for convenience.
buildah \
    --signature-policy=./policy.json \
    commit --rm "${container}" "${image}:${ghcup_version}"
