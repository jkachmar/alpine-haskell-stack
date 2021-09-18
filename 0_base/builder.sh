#!/usr/bin/env sh
set -eu

# Start the script in the top-level repository directory no matter what.
cd "$( git rev-parse --show-toplevel )"

# XXX: Would it make sense to pull from an existing image if one exists?
image="alpine-ghc-base"
container="alpine-ghc-base-builder"

################################################################################
# Attempt to create a new image using the container name defined above.
#
# If the container already exists, assume that it's been created by a previous
# run of this script and just use that.
buildah \
    --signature-policy=./policy.json \
    --name "${container}" \
    from --pull docker.io/library/alpine:3.14 \
    || true

# Upgrade the currently installed packages.
#
# NOTE: This breaks reproducibility.
buildah run "${container}" \
    apk upgrade --no-cache

# Install basic dependencies required by 'ghcup', 'stack', and 'cabal-install'.
buildah run "${container}" \
    apk add --no-cache \
      curl \
      gcc \
      git \
      libc-dev \
      xz

# TODO: Guard this behind some argument that can toggle GMP-based builds.
echo "Installing 'libgmp'."
buildah run "${container}" \
    apk add --no-cache gmp-dev

################################################################################
ghcup_version="0.1.9"
ghcup_expected_checksum="d779ada6156b08da21e40c5bf218ec21d1308d5a9e48f7b9533f56b5d063a41c"

# Fetch `ghcup`.
buildah run "${container}" \
    wget \
        -O "/tmp/ghcup-${ghcup_version}" \
        "https://downloads.haskell.org/~ghcup/0.1.9/x86_64-linux-ghcup-${ghcup_version}"

# Copy the checksum validation script into the container...
buildah copy --chmod 111 ${container} \
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

# ...and clean up after ourselves.
buildah run "${container}" \
    rm -rf /tmp/validate_checksum.sh

################################################################################
# Write the final `alpine-ghc-base` image from this container.
buildah \
    --signature-policy=./policy.json \
    commit "${container}" "${image}"
