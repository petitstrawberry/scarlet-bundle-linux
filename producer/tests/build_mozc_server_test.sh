#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
BUILD_SCRIPT="${REPO_ROOT}/producer/tools/build_mozc_server.sh"

assert_contains() {
    local expected="$1"

    if ! grep -Fq -- "${expected}" "${BUILD_SCRIPT}"; then
        echo "Expected ${BUILD_SCRIPT} to contain: ${expected}" >&2
        exit 1
    fi
}

bash -n "${BUILD_SCRIPT}"
assert_contains 'cat > "${toolchain_pkg_dir}/cc_toolchain_config.bzl"'
assert_contains 'cc_common.create_cc_toolchain_config_info('
assert_contains 'load("@rules_cc//cc:action_names.bzl", "ACTION_NAMES")'
assert_contains 'load("@rules_cc//cc/common:cc_common.bzl", "cc_common")'
assert_contains 'load("@rules_cc//cc/toolchains:cc_toolchain_config_info.bzl", "CcToolchainConfigInfo")'
assert_contains 'load("@rules_cc//cc:defs.bzl", "cc_toolchain")'
assert_contains 'enabled = True'
assert_contains 'tool_path(name = "gcov", path = "${toolchain_gcov}")'
assert_contains '"-lstdc++"'
assert_contains '"-lm"'
assert_contains '"--verbose_failures"'
assert_contains '"--experimental_ui_max_stdouterr_bytes=10485760"'
assert_contains 'toolchain = ":buildroot_cc"'
assert_contains 'toolchain_type = "@bazel_tools//tools/cpp:toolchain_type"'
assert_contains '"@platforms//cpu:x86_64"'
assert_contains '"@platforms//cpu:${BAZEL_CPU}"'
assert_contains '"--platforms=//scarlet_buildroot_cc:linux_${BAZEL_CPU}"'
assert_contains '"--extra_toolchains=//scarlet_buildroot_cc:buildroot_cc_linux_${BAZEL_CPU}"'
assert_contains '"--host_crosstool_top=@bazel_tools//tools/cpp:toolchain"'
assert_contains '"--repo_env=BAZEL_TARGET_CPU=${BAZEL_CPU}"'

for forbidden in \
    'toolchain = "@local_config_cc//:cc-compiler-k8"' \
    '"--repo_env=CC=${toolchain_gcc}"' \
    '"--repo_env=CXX=${toolchain_gxx}"' \
    '"--action_env=CC=${toolchain_gcc}"' \
    '"--action_env=CXX=${toolchain_gxx}"' \
    '"--copt=--sysroot=${toolchain_sysroot}"' \
    '"--linkopt=-lfts"'; do
    if grep -Fq -- "${forbidden}" "${BUILD_SCRIPT}"; then
        echo "Forbidden global target toolchain setting remains: ${forbidden}" >&2
        exit 1
    fi
done

if grep -Fq -- '"--crosstool_top=@local_config_cc//:toolchain"' "${BUILD_SCRIPT}"; then
    echo "Legacy --crosstool_top configuration must not be used." >&2
    exit 1
fi
