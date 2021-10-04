#!/usr/bin/env sh

ghcup_img="$1"
builder_cntr="$2"

ghcup_cntr=$(buildah from --signature-policy=./policy.json "${ghcup_img}")
ghcup_mnt=$(buildah mount "${ghcup_cntr}")
builder_mnt=$(buildah mount "${builder_cntr}")

cp "${ghcup_mnt}/usr/bin/ghcup" "${builder_mnt}/usr/bin/ghcup"

# Clean up intermediate container.
buildah rm "${ghcup_cntr}"
