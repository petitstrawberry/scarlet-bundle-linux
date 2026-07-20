#!/usr/bin/env bash
set -euo pipefail

# Print a file's SHA-256 in the cargo-scarlet manifest format.
# Usage: scripts/compute-artifact-hash.sh <file>

if [[ $# -ne 1 ]]; then
    echo "Usage: $0 <file>" >&2
    exit 2
fi

file="$1"
if [[ ! -f "${file}" ]]; then
    echo "error: artifact file not found: ${file}" >&2
    exit 1
fi

read -r hash _ < <(sha256sum "${file}")
printf 'sha256:%s\n' "${hash,,}"
