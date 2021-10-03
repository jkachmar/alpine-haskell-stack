#!/usr/bin/env sh

ghcup_img="$1"
builder_cnt="$2"

ghcup_cnt=$(buildah from --signature-policy=./policy.json "${ghcup_img}")
ghcup_mnt=$(buildah mount "${ghcup_cnt}")
builder_mnt=$(buildah mount "${builder_cnt}")

cp "${ghcup_mnt}/usr/bin/ghcup" "${builder_mnt}/usr/bin/ghcup"

# Clean up intermediate container.
buildah rm "${ghcup_cnt}"
