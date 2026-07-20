#!/bin/bash
set -euo pipefail

# Builds Buildroot using the repository-provided configuration.
# Environment variables:
#  ARCH - target architecture (riscv64 or aarch64), defaults to riscv64
#  BUILDROOT_DIR - Buildroot tree; defaults to the Docker path for ARCH
#  PREBUILT_DIR - artifact staging directory, defaults to bundles/linux/prebuilt
#  IMAGES_DIR - Buildroot images directory, defaults to output/images
#  MAKE_JOBS - Buildroot parallelism, defaults to $(nproc)
#  BUILDROOT_VERSION - Buildroot release to use when bootstrapping AArch64

: "${ARCH:=riscv64}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUNDLE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
: "${BUILDROOT_VERSION:=2025.02.6}"
: "${PREBUILT_DIR:=${BUNDLE_DIR}/prebuilt}"
: "${IMAGES_DIR:=output/images}"

require_supported_host() {
    if [[ "$(uname -s)" != "Darwin" ]]; then
        return
    fi

    cat >&2 <<EOF
Buildroot artifacts are generated on Linux hosts only.
macOS can still build Scarlet itself, but Buildroot's host tools and generated
toolchains should be produced in scarlet-dev, a Linux VM, or a Linux Nix shell.

Example with repository-local paths:
  ARCH=${ARCH} \\
  BUILDROOT_DIR="\$PWD/bundles/linux/cache/buildroot-${ARCH}" \\
  PREBUILT_DIR="\$PWD/bundles/linux/prebuilt" \\
  bash "${SCRIPT_DIR}/build_buildroot.sh"
EOF
    exit 1
}

case "${ARCH}" in
    riscv64)
        : "${BUILDROOT_DIR:=/opt/buildroot}"
        ;;
    aarch64)
        : "${BUILDROOT_DIR:=/opt/buildroot-aarch64}"
        ;;
    *)
        echo "Unsupported architecture: ${ARCH}" >&2
        exit 1
        ;;
esac

if [[ "${SCARLET_BUNDLE_SKIP_HOST_CHECK:-0}" != "1" ]]; then
    require_supported_host
fi
: "${MAKE_JOBS:=$(nproc)}"

download_file() {
    local url="$1"
    local output="$2"

    if command -v curl >/dev/null 2>&1; then
        curl -fL "${url}" -o "${output}"
    elif command -v wget >/dev/null 2>&1; then
        wget -O "${output}" "${url}"
    else
        echo "Neither curl nor wget is available to download ${url}" >&2
        exit 1
    fi
}

ensure_buildroot_release() {
    if [[ -d "${BUILDROOT_DIR}" && -d "${BUILDROOT_DIR}/.git" ]]; then
        local current_version
        current_version="$(make -C "${BUILDROOT_DIR}" -s printvars VARS=BR2_VERSION_FULL 2>/dev/null | sed -n 's/^BR2_VERSION_FULL=//p')"
        if [[ "${current_version}" != "${BUILDROOT_VERSION}" ]]; then
            echo "==> Switching Buildroot from ${current_version:-unknown} to ${BUILDROOT_VERSION}..."
            git -C "${BUILDROOT_DIR}" fetch --depth=1 origin "refs/tags/${BUILDROOT_VERSION}:refs/tags/${BUILDROOT_VERSION}"
            git -C "${BUILDROOT_DIR}" checkout "${BUILDROOT_VERSION}"
        fi
        return
    fi

    if [[ -d "${BUILDROOT_DIR}" ]]; then
        local current_version
        current_version="$(make -C "${BUILDROOT_DIR}" -s printvars VARS=BR2_VERSION_FULL 2>/dev/null | sed -n 's/^BR2_VERSION_FULL=//p')"
        if [[ "${current_version}" != "${BUILDROOT_VERSION}" ]]; then
            echo "Buildroot tree at ${BUILDROOT_DIR} is ${current_version:-unknown}, expected ${BUILDROOT_VERSION}." >&2
            echo "Remove it or set BUILDROOT_DIR to a Buildroot ${BUILDROOT_VERSION} tree." >&2
            exit 1
        fi
        return
    fi

    local archive="buildroot-${BUILDROOT_VERSION}.tar.gz"
    local cache_dir
    cache_dir="$(dirname "${BUILDROOT_DIR}")"

    echo "==> Downloading Buildroot ${BUILDROOT_VERSION}..."
    mkdir -p "${cache_dir}"
    download_file "https://buildroot.org/downloads/${archive}" "${cache_dir}/${archive}"
    tar -xf "${cache_dir}/${archive}" -C "${cache_dir}"
    mv "${cache_dir}/buildroot-${BUILDROOT_VERSION}" "${BUILDROOT_DIR}"
}

configure_common_linux_userland() {
    source "${REPO_ROOT}/producer/buildroot/configs/common_linux_userland.sh"
}

build_riscv64() {
    ensure_buildroot_release

    pushd "${BUILDROOT_DIR}" >/dev/null
    if [[ ! -f .config ]]; then
        cp "${REPO_ROOT}/producer/buildroot/configs/scarlet_riscv64_defconfig" .config
    fi
    make olddefconfig
    make -j "${MAKE_JOBS}"

    if [[ ! -d "${IMAGES_DIR}" ]]; then
        echo "Images directory ${BUILDROOT_DIR}/${IMAGES_DIR} missing after build." >&2
        exit 1
    fi

    pushd "${IMAGES_DIR}" >/dev/null
    rm -rf linux-riscv64
    mkdir linux-riscv64
    if [[ ! -f rootfs.tar ]]; then
        echo "rootfs.tar not found in ${BUILDROOT_DIR}/${IMAGES_DIR}." >&2
        exit 1
    fi

    tar -xf rootfs.tar -C linux-riscv64
    mkdir -p "${PREBUILT_DIR}/riscv64"
    cp rootfs.tar "${PREBUILT_DIR}/riscv64/rootfs.tar"

    popd >/dev/null
    popd >/dev/null
}

build_aarch64() {
    ensure_buildroot_release

    pushd "${BUILDROOT_DIR}" >/dev/null

    echo "==> Configuring Buildroot ${BUILDROOT_VERSION} for aarch64..."
    make qemu_aarch64_virt_defconfig
    configure_common_linux_userland
    make olddefconfig

    toolchain_gxx="${BUILDROOT_DIR}/output/host/bin/aarch64-buildroot-linux-musl-g++"
    if [[ ! -x "${toolchain_gxx}" ]]; then
        echo "==> C++ toolchain missing; rebuilding Buildroot gcc for aarch64..."
        make host-gcc-final-dirclean gcc-final-dirclean
    fi

    echo "==> Building Buildroot toolchain + rootfs for aarch64 (this takes a while)..."
    make -j "${MAKE_JOBS}"

    if [[ ! -f "${IMAGES_DIR}/rootfs.tar" ]]; then
        echo "ERROR: rootfs.tar not found in ${IMAGES_DIR}." >&2
        exit 1
    fi

    mkdir -p "${PREBUILT_DIR}/aarch64"
    cp "${IMAGES_DIR}/rootfs.tar" "${PREBUILT_DIR}/aarch64/rootfs.tar"

    popd >/dev/null

    toolchain_gcc="${BUILDROOT_DIR}/output/host/bin/aarch64-buildroot-linux-musl-gcc"
    if [[ ! -x "${toolchain_gcc}" ]]; then
        echo "ERROR: toolchain gcc not found at ${toolchain_gcc}" >&2
        exit 1
    fi

    echo ""
    echo "==> Buildroot aarch64 built successfully!"
    echo "    Toolchain: ${toolchain_gcc}"
    echo "    Rootfs:    ${PREBUILT_DIR}/aarch64/rootfs.tar"
}

case "${ARCH}" in
    riscv64)
        build_riscv64
        ;;
    aarch64)
        build_aarch64
        ;;
esac

echo "Buildroot artifacts staged under ${PREBUILT_DIR}."
