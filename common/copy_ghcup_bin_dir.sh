#!/usr/bin/env sh

ghcup_img="$1"
builder_cntr="$2"

ghcup_cntr=$(buildah from --signature-policy=./policy.json "${ghcup_img}")
ghcup_mnt=$(buildah mount "${ghcup_cntr}")
builder_mnt=$(buildah mount "${builder_cntr}")

cp -r "${ghcup_mnt}/root/.ghcup" "${builder_mnt}/root/.ghcup"

# Clean up intermediate container.
buildah rm "${ghcup_cntr}"
