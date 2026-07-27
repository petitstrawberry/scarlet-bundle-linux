#!/usr/bin/env bash
set -euo pipefail

# Package the Mozc server staged by build_mozc_server.sh.
# The archive contains ./usr/lib/mozc/mozc_server so it can be applied as a
# separate layer at /system/linux-<arch>.

: "${ARCH:=aarch64}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
BUNDLE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd -P)"
: "${PREBUILT_DIR:=${BUNDLE_DIR}/prebuilt}"
: "${ARTIFACT_DIR:=${BUNDLE_DIR}/artifacts}"
: "${BUILDROOT_DIR:=${BUNDLE_DIR}/cache/buildroot-${ARCH}}"

case "${ARCH}" in
    riscv64|aarch64)
        ;;
    *)
        echo "Unsupported ARCH=${ARCH}. Use riscv64 or aarch64." >&2
        exit 1
        ;;
esac

stage_root="${PREBUILT_DIR}/${ARCH}/root"
mozc_binary="${stage_root}/usr/lib/mozc/mozc_server"
host_zstd="${BUILDROOT_DIR}/output/host/bin/zstd"
output_archive="${ARTIFACT_DIR}/mozc-${ARCH}.tar.zst"

if [[ ! -x "${mozc_binary}" ]]; then
    echo "Mozc server is missing or not executable: ${mozc_binary}" >&2
    echo "Run build_mozc_server.sh first." >&2
    exit 1
fi
if [[ ! -x "${host_zstd}" ]]; then
    echo "Buildroot host-zstd is missing: ${host_zstd}" >&2
    exit 1
fi

mkdir -p "${ARTIFACT_DIR}"
tar --sort=name --mtime='@0' --owner=0 --group=0 --numeric-owner \
    --pax-option=delete=atime,delete=ctime \
    -C "${stage_root}" -cf - . | \
    "${host_zstd}" -q --no-progress -19 -T1 -f -o "${output_archive}"

echo "Packaged Mozc: ${output_archive}"
