#!/usr/bin/env bash
set -euo pipefail

# Discover and pin a fixed-output Nix hash, then retry the build.
# Usage: scripts/bootstrap-hash.sh <flake-ref> <attribute>

if [[ $# -ne 2 ]]; then
    echo "Usage: $0 <flake-ref> <attribute>" >&2
    exit 2
fi

flake_ref="$1"
attribute="$2"
target="${flake_ref}#${attribute}"
flake_file="${flake_ref%/}/flake.nix"

if [[ ! -f "${flake_file}" ]]; then
    echo "error: flake file not found: ${flake_file}" >&2
    exit 1
fi

if nix --extra-experimental-features 'nix-command flakes' build "${target}" --no-link --print-out-paths 2>&1 | tee /tmp/build.log; then
    echo "build succeeded on first attempt"
    exit 0
fi

got_line="$(grep -Em1 'got:[[:space:]]+sha256-[A-Za-z0-9+/=]+' /tmp/build.log || true)"
if [[ ! "${got_line}" =~ got:[[:space:]]+(sha256-[A-Za-z0-9+/=]+) ]]; then
    echo "error: build failed without a fixed-output hash mismatch" >&2
    exit 1
fi
got_hash="${BASH_REMATCH[1]}"

python3 - "${flake_file}" "${got_hash}" <<'PY'
import pathlib
import sys

flake_path = pathlib.Path(sys.argv[1])
got_hash = sys.argv[2]
placeholder = "outputHash = pkgs.lib.fakeSha256;"
replacement = f'outputHash = "{got_hash}";'
contents = flake_path.read_text()

if placeholder not in contents:
    print(f"error: placeholder not found in {flake_path}", file=sys.stderr)
    raise SystemExit(1)

flake_path.write_text(contents.replace(placeholder, replacement, 1))
PY

if nix --extra-experimental-features 'nix-command flakes' build "${target}" --no-link --print-out-paths 2>&1 | tee /tmp/build.log; then
    exit 0
fi

echo "error: build failed after pinning fixed-output hash ${got_hash}" >&2
exit 1
