#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd -P)"
BUILD_SCRIPT="${REPO_ROOT}/producer/tools/build_buildroot.sh"
RISCV64_DEFCONFIG="${REPO_ROOT}/producer/buildroot/external/configs/scarlet_riscv64_defconfig"
AARCH64_DEFCONFIG="${REPO_ROOT}/producer/buildroot/external/configs/scarlet_aarch64_defconfig"
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/scarlet-buildroot-direct.XXXXXX")"
trap 'rm -rf "${TEST_DIR}"' EXIT

FAKE_BIN_DIR="${TEST_DIR}/bin"
mkdir -p "${FAKE_BIN_DIR}"

cat > "${FAKE_BIN_DIR}/uname" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "${SCARLET_TEST_UNAME_OS:-Linux}"
EOF
chmod +x "${FAKE_BIN_DIR}/uname"

assert_file_contains() {
    local file="$1"
    local expected="$2"

    if ! grep -F -- "${expected}" "${file}" >/dev/null; then
        echo "build_buildroot_test: ${file} is missing: ${expected}" >&2
        exit 1
    fi
}

assert_file_excludes() {
    local file="$1"
    local pattern="$2"

    if grep -Eq -- "${pattern}" "${file}"; then
        echo "build_buildroot_test: ${file} unexpectedly matches: ${pattern}" >&2
        exit 1
    fi
}

run_expect_failure() {
    local expected="$1"
    local output

    shift
    if output="$("$@" 2>&1)"; then
        echo "build_buildroot_test: command unexpectedly succeeded: $*" >&2
        exit 1
    fi
    if [[ "${output}" != *"${expected}"* ]]; then
        echo "build_buildroot_test: expected error not found: ${expected}" >&2
        printf '%s\n' "${output}" >&2
        exit 1
    fi
}

TEST_PATH="${FAKE_BIN_DIR}:${PATH}"

run_expect_failure "Buildroot rootfs artifacts require a normal Linux host." \
    env "PATH=${TEST_PATH}" SCARLET_TEST_UNAME_OS=Darwin bash "${BUILD_SCRIPT}"
run_expect_failure "Unsupported ARCH=x86_64." \
    env "PATH=${TEST_PATH}" SCARLET_TEST_UNAME_OS=Linux ARCH=x86_64 bash "${BUILD_SCRIPT}"
run_expect_failure "MAKE_JOBS must be a positive integer, got 0." \
    env "PATH=${TEST_PATH}" SCARLET_TEST_UNAME_OS=Linux MAKE_JOBS=0 bash "${BUILD_SCRIPT}"
run_expect_failure "Unsupported BUILDROOT_BUILD_MODE=invalid." \
    env "PATH=${TEST_PATH}" SCARLET_TEST_UNAME_OS=Linux BUILDROOT_BUILD_MODE=invalid bash "${BUILD_SCRIPT}"

assert_file_contains "${BUILD_SCRIPT}" 'readonly BUILDROOT_VERSION="2025.02.6"'
assert_file_contains "${BUILD_SCRIPT}" 'readonly BUILDROOT_TARBALL_SHA256="aa2aea04ff5d70dcbae7474ffc63f3f580e94e7f8839c074d96dfdb9abf78911"'
assert_file_contains "${BUILD_SCRIPT}" 'patch --batch --fuzz=0 -p1'
assert_file_contains "${BUILD_SCRIPT}" '"BR2_DL_DIR=${BUILDROOT_DL_DIR}"'
assert_file_contains "${BUILD_SCRIPT}" '"O=${OUTPUT_DIR}"'
assert_file_contains "${BUILD_SCRIPT}" '"BR2_EXTERNAL=${EXTERNAL_DIR}"'
assert_file_contains "${BUILD_SCRIPT}" 'buildroot_make legal-info'
assert_file_contains "${BUILD_SCRIPT}" 'legal-info/scarlet-buildroot-patches'
assert_file_contains "${BUILD_SCRIPT}" 'tar --sort=name --mtime='"'"'@0'"'"' --owner=0 --group=0 --numeric-owner'
assert_file_excludes "${BUILD_SCRIPT}" 'docker|podman|container|SCARLET_BUILDROOT_CONTAINER|build_buildroot_inner|--mount'
assert_file_excludes "${BUILD_SCRIPT}" 'utils/config.*BR2_DL_DIR|--set-str BR2_DL_DIR'

for defconfig in "${RISCV64_DEFCONFIG}" "${AARCH64_DEFCONFIG}"; do
    assert_file_contains "${defconfig}" 'BR2_DOWNLOAD_FORCE_CHECK_HASHES=y'
    assert_file_contains "${defconfig}" 'BR2_REPRODUCIBLE=y'
    assert_file_contains "${defconfig}" 'BR2_PACKAGE_HOST_ZSTD=y'
done

printf '%s\n' 'build_buildroot_test: PASS'
