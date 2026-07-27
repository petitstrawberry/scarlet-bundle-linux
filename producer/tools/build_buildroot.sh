#!/usr/bin/env bash
set -euo pipefail

# Build Buildroot directly on a normal Linux host.
# Environment variables:
#  ARCH                 - target architecture (riscv64 or aarch64)
#  BUILDROOT_DIR        - per-architecture Buildroot work directory
#  PREBUILT_DIR         - rootfs staging directory for downstream tools
#  ARTIFACT_DIR         - compressed rootfs and legal-info output directory
#  BUILDROOT_DL_DIR     - shared Buildroot download cache directory
#  MAKE_JOBS            - Buildroot parallelism
#  BUILDROOT_BUILD_MODE - build (default) or configure

readonly BUILDROOT_VERSION="2025.02.6"
readonly BUILDROOT_TARBALL="buildroot-${BUILDROOT_VERSION}.tar.gz"
readonly BUILDROOT_TARBALL_URL="https://buildroot.org/downloads/${BUILDROOT_TARBALL}"
readonly BUILDROOT_TARBALL_SHA256="aa2aea04ff5d70dcbae7474ffc63f3f580e94e7f8839c074d96dfdb9abf78911"

if [[ "$(uname -s)" != "Linux" ]]; then
    cat >&2 <<'EOF'
Buildroot rootfs artifacts require a normal Linux host.
Run this script on Ubuntu 24.04 or another supported Linux environment.
EOF
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
BUNDLE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd -P)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd -P)"
EXTERNAL_DIR="${REPO_ROOT}/producer/buildroot/external"
PATCH_DIR="${REPO_ROOT}/producer/buildroot/patches"

: "${ARCH:=riscv64}"
: "${PREBUILT_DIR:=${BUNDLE_DIR}/prebuilt}"
: "${ARTIFACT_DIR:=${BUNDLE_DIR}/artifacts}"
: "${BUILDROOT_DL_DIR:=${BUNDLE_DIR}/cache/buildroot-dl}"
: "${BUILDROOT_BUILD_MODE:=build}"

default_make_jobs() {
    if command -v nproc >/dev/null 2>&1; then
        nproc
    elif command -v getconf >/dev/null 2>&1; then
        getconf _NPROCESSORS_ONLN
    else
        printf '%s\n' 4
    fi
}

: "${MAKE_JOBS:=$(default_make_jobs)}"

case "${ARCH}" in
    riscv64|aarch64)
        : "${BUILDROOT_DIR:=${BUNDLE_DIR}/cache/buildroot-${ARCH}}"
        DEFCONFIG="scarlet_${ARCH}_defconfig"
        ;;
    *)
        echo "Unsupported ARCH=${ARCH}. Use riscv64 or aarch64." >&2
        exit 1
        ;;
esac

case "${BUILDROOT_BUILD_MODE}" in
    build|configure)
        ;;
    *)
        echo "Unsupported BUILDROOT_BUILD_MODE=${BUILDROOT_BUILD_MODE}. Use build or configure." >&2
        exit 1
        ;;
esac

if [[ ! "${MAKE_JOBS}" =~ ^[1-9][0-9]*$ ]]; then
    echo "MAKE_JOBS must be a positive integer, got ${MAKE_JOBS}." >&2
    exit 1
fi

for required_command in awk bc bzip2 cpio diff file find g++ gcc git gzip ld make patch perl python3 rsync sed sha256sum tar unzip wget which xzcat; do
    if ! command -v "${required_command}" >/dev/null 2>&1; then
        echo "Required Linux Buildroot command is unavailable: ${required_command}" >&2
        exit 1
    fi
done

canonicalize_writable_dir() {
    local path="$1"

    mkdir -p "${path}"
    (cd "${path}" && pwd -P)
}

assert_safe_writable_dir() {
    local path="$1"
    local description="$2"

    if [[ "${path}" == "/" || "${path}" == "${REPO_ROOT}" ]]; then
        echo "Refusing to use ${description} at ${path}." >&2
        exit 1
    fi
}

BUILDROOT_DIR="$(canonicalize_writable_dir "${BUILDROOT_DIR}")"
PREBUILT_DIR="$(canonicalize_writable_dir "${PREBUILT_DIR}")"
ARTIFACT_DIR="$(canonicalize_writable_dir "${ARTIFACT_DIR}")"
BUILDROOT_DL_DIR="$(canonicalize_writable_dir "${BUILDROOT_DL_DIR}")"

assert_safe_writable_dir "${BUILDROOT_DIR}" "BUILDROOT_DIR"
assert_safe_writable_dir "${PREBUILT_DIR}" "PREBUILT_DIR"
assert_safe_writable_dir "${ARTIFACT_DIR}" "ARTIFACT_DIR"
assert_safe_writable_dir "${BUILDROOT_DL_DIR}" "BUILDROOT_DL_DIR"

SOURCE_DIR="${BUILDROOT_DIR}/source"
OUTPUT_DIR="${BUILDROOT_DIR}/output"
SOURCE_ARCHIVE="${BUILDROOT_DL_DIR}/${BUILDROOT_TARBALL}"

if [[ ! -f "${EXTERNAL_DIR}/external.desc" || ! -f "${EXTERNAL_DIR}/configs/${DEFCONFIG}" ]]; then
    echo "Scarlet Buildroot external tree is incomplete: ${EXTERNAL_DIR}" >&2
    exit 1
fi

verify_source_archive() {
    local actual_sha256

    read -r actual_sha256 _ < <(sha256sum "${SOURCE_ARCHIVE}")
    if [[ "${actual_sha256}" != "${BUILDROOT_TARBALL_SHA256}" ]]; then
        echo "Buildroot ${BUILDROOT_VERSION} archive checksum mismatch." >&2
        echo "Expected: ${BUILDROOT_TARBALL_SHA256}" >&2
        echo "Actual:   ${actual_sha256}" >&2
        return 1
    fi
}

download_source_archive() {
    local temporary_archive

    if [[ -f "${SOURCE_ARCHIVE}" ]] && verify_source_archive; then
        return
    fi

    rm -f "${SOURCE_ARCHIVE}"
    temporary_archive="${BUILDROOT_DL_DIR}/.${BUILDROOT_TARBALL}.$$"
    rm -f "${temporary_archive}"

    echo "==> Downloading Buildroot ${BUILDROOT_VERSION}..."
    if ! wget --no-verbose --output-document="${temporary_archive}" "${BUILDROOT_TARBALL_URL}"; then
        rm -f "${temporary_archive}"
        echo "Unable to download ${BUILDROOT_TARBALL_URL}." >&2
        exit 1
    fi

    mv -f "${temporary_archive}" "${SOURCE_ARCHIVE}"
    verify_source_archive
}

extract_clean_source_tree() {
    local extraction_dir
    local extracted_source_dir

    extraction_dir="$(mktemp -d "${BUILDROOT_DIR}/.source-${BUILDROOT_VERSION}.XXXXXX")"
    extracted_source_dir="${extraction_dir}/buildroot-${BUILDROOT_VERSION}"

    if ! tar -xzf "${SOURCE_ARCHIVE}" -C "${extraction_dir}"; then
        rm -rf "${extraction_dir}"
        echo "Unable to extract ${SOURCE_ARCHIVE}." >&2
        exit 1
    fi

    if [[ ! -d "${extracted_source_dir}" ]]; then
        rm -rf "${extraction_dir}"
        echo "Buildroot archive did not contain buildroot-${BUILDROOT_VERSION}." >&2
        exit 1
    fi

    rm -rf "${SOURCE_DIR}"
    mv "${extracted_source_dir}" "${SOURCE_DIR}"
    rmdir "${extraction_dir}"
}

apply_buildroot_patches() {
    local patch_file

    for patch_file in \
        "${PATCH_DIR}/0001-exclude-listmount-statmount-for-musl.patch" \
        "${PATCH_DIR}/0004-freetype-use-host-compiler.patch"; do
        if [[ ! -f "${patch_file}" ]]; then
            echo "Missing retained Buildroot source patch: ${patch_file}" >&2
            exit 1
        fi
        (
            cd "${SOURCE_DIR}"
            patch --batch --fuzz=0 -p1 < "${patch_file}"
        )
    done
}

buildroot_make() {
    make -C "${SOURCE_DIR}" \
        "O=${OUTPUT_DIR}" \
        "BR2_EXTERNAL=${EXTERNAL_DIR}" \
        "BR2_DL_DIR=${BUILDROOT_DL_DIR}" \
        "$@"
}

assert_config_option() {
    local option="$1"

    if ! grep -Fx -- "${option}" "${OUTPUT_DIR}/.config" >/dev/null; then
        echo "Configured Buildroot output is missing ${option}." >&2
        exit 1
    fi
}

configure_buildroot() {
    echo "==> Configuring Buildroot ${BUILDROOT_VERSION} for ${ARCH}..."
    buildroot_make "${DEFCONFIG}"
    buildroot_make olddefconfig

    assert_config_option "BR2_DOWNLOAD_FORCE_CHECK_HASHES=y"
    assert_config_option "BR2_REPRODUCIBLE=y"
    assert_config_option "BR2_PACKAGE_HOST_ZSTD=y"
}

archive_release_outputs() {
    local rootfs_tar="${OUTPUT_DIR}/images/rootfs.tar"
    local staged_rootfs="${PREBUILT_DIR}/${ARCH}/rootfs.tar"
    local host_zstd="${OUTPUT_DIR}/host/bin/zstd"
    local rootfs_archive="${ARTIFACT_DIR}/rootfs-${ARCH}.tar.zst"
    local legal_info_archive="${ARTIFACT_DIR}/legal-info-${ARCH}.tar.zst"
    local legal_patch_dir="${OUTPUT_DIR}/legal-info/scarlet-buildroot-patches"

    if [[ ! -f "${rootfs_tar}" ]]; then
        echo "Buildroot did not produce ${rootfs_tar}." >&2
        exit 1
    fi

    if [[ ! -x "${host_zstd}" ]]; then
        echo "==> Building Buildroot host-zstd..."
        buildroot_make "-j${MAKE_JOBS}" host-zstd
    fi
    if [[ ! -x "${host_zstd}" ]]; then
        echo "Buildroot host-zstd is missing at ${host_zstd}." >&2
        exit 1
    fi

    echo "==> Collecting Buildroot legal information..."
    buildroot_make legal-info
    if [[ ! -d "${OUTPUT_DIR}/legal-info" ]]; then
        echo "Buildroot did not produce ${OUTPUT_DIR}/legal-info." >&2
        exit 1
    fi

    mkdir -p "${legal_patch_dir}"
    cp -p \
        "${PATCH_DIR}/0001-exclude-listmount-statmount-for-musl.patch" \
        "${PATCH_DIR}/0004-freetype-use-host-compiler.patch" \
        "${legal_patch_dir}/"

    mkdir -p "${PREBUILT_DIR}/${ARCH}" "${ARTIFACT_DIR}"
    cp -p "${rootfs_tar}" "${staged_rootfs}"

    "${host_zstd}" -q --no-progress -19 -T1 -f \
        -o "${rootfs_archive}" "${staged_rootfs}"
    tar --sort=name --mtime='@0' --owner=0 --group=0 --numeric-owner \
        --pax-option=delete=atime,delete=ctime \
        -C "${OUTPUT_DIR}" -cf - legal-info | \
        "${host_zstd}" -q --no-progress -19 -T1 -f -o "${legal_info_archive}"

    echo "==> Staged rootfs: ${staged_rootfs}"
    echo "==> Release rootfs: ${rootfs_archive}"
    echo "==> Release legal-info: ${legal_info_archive}"
}

download_source_archive
extract_clean_source_tree
apply_buildroot_patches
configure_buildroot

if [[ "${BUILDROOT_BUILD_MODE}" == "configure" ]]; then
    echo "Buildroot configuration validated at ${OUTPUT_DIR}/.config."
    exit 0
fi

echo "==> Building Buildroot rootfs for ${ARCH}..."
buildroot_make "-j${MAKE_JOBS}"
archive_release_outputs
