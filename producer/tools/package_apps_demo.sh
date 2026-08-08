#!/usr/bin/env bash
set -euo pipefail

# Package the user-space demo programs staged by build_user_programs.sh.
# The archive contains ./usr/bin, ./usr/lib, and ./usr/share so it can be
# applied as a separate layer at /system/linux-<arch>.
#
# Environment variables:
#  ARCH           - target architecture (riscv64 or aarch64), defaults to aarch64
#  PREBUILT_DIR   - artifact staging directory, defaults to ../prebuilt
#  ARTIFACT_DIR   - compressed archive output directory, defaults to ../artifacts
#  BUILDROOT_DIR  - Buildroot work directory (provides host-zstd)

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

host_zstd="${BUILDROOT_DIR}/output/host/bin/zstd"
output_archive="${ARTIFACT_DIR}/apps-demo-${ARCH}.tar.zst"
stage_root="${PREBUILT_DIR}/${ARCH}/apps-root"

# Artifacts staged by build_guest_image.sh belong to the shv-guest bundle and
# are intentionally not part of the apps-demo layer.
readonly SHV_GUEST_ARTIFACTS=(guest-Image guest-initramfs.cpio.gz)

if [[ ! -x "${host_zstd}" ]]; then
    echo "Buildroot host-zstd is missing: ${host_zstd}" >&2
    echo "Run build_buildroot.sh first." >&2
    exit 1
fi

rm -rf "${stage_root}"
mkdir -p "${stage_root}/usr"

staged_files=0
for subdir in bin lib share; do
    source_dir="${PREBUILT_DIR}/${ARCH}/${subdir}"
    if [[ ! -d "${source_dir}" ]]; then
        continue
    fi

    target_dir="${stage_root}/usr/${subdir}"
    mkdir -p "${target_dir}"
    shopt -s nullglob
    for entry in "${source_dir}"/*; do
        basename_entry="$(basename "${entry}")"
        if [[ " ${SHV_GUEST_ARTIFACTS[*]} " == *" ${basename_entry} "* ]]; then
            echo "Excluding shv-guest artifact: ${basename_entry}"
            continue
        fi
        cp -a "${entry}" "${target_dir}/"
        staged_files=$((staged_files + 1))
    done
    shopt -u nullglob
    rmdir "${target_dir}" 2>/dev/null || true
done

if [[ "${staged_files}" -eq 0 ]]; then
    echo "No user programs staged at ${PREBUILT_DIR}/${ARCH}/{bin,lib,share}." >&2
    echo "Run build_user_programs.sh first." >&2
    rm -rf "${stage_root}"
    exit 1
fi

mkdir -p "${ARTIFACT_DIR}"
tar --sort=name --mtime='@0' --owner=0 --group=0 --numeric-owner \
    --pax-option=delete=atime,delete=ctime \
    -C "${stage_root}" -cf - . | \
    "${host_zstd}" -q --no-progress -19 -T1 -f -o "${output_archive}"

echo "Packaged apps-demo: ${output_archive}"
echo "Staged ${staged_files} file(s) under usr/{bin,lib,share}"
