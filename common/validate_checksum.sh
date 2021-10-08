#!/usr/bin/env sh
set -eu

file_path="$1"
expected_checksum="$2"

if ! echo "${expected_checksum}  ${file_path}" | sha256sum -c -; then
    echo "${file_path} checksum failed" >&2
    echo "expected '${expected_checksum}', but got '$( sha256sum "${file_path}" )'" >&2
    exit 1
fi;
