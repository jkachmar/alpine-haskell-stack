#!/usr/bin/env sh
set -eu

ghcup_path=$1
ghcup_expected_checksum="$2"

if ! echo "${ghcup_expected_checksum}  ${ghcup_path}" | sha256sum -c -; then
    echo "${ghcup_path} checksum failed" >&2
    echo "expected '${ghcup_expected_checksum}', but got '$( sha256sum "${ghcup_path}" )'" >&2
    exit 1
fi;
