#!/usr/bin/env sh
set -eu

ghc_ver=$1

LD=ld.gold \
SPHINXBUILD=/usr/bin/sphinx-build-3 \
    ghcup \
        --verbose \
        compile ghc \
        --jobs "$(nproc)" \
        --config /tmp/build.mk \
        --patchdir /tmp/patches \
        --bootstrap-ghc /usr/bin/ghc \
        --set \
        --version "${ghc_ver}"
