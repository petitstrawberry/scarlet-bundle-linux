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
assert_contains 'local platform_name="linux_${BAZEL_CPU}"'
assert_contains 'name = "${toolchain_name}"'
assert_contains 'toolchain = "@local_config_cc//:cc-compiler-k8"'
assert_contains 'toolchain_type = "@bazel_tools//tools/cpp:toolchain_type"'
assert_contains '"@platforms//cpu:x86_64"'
assert_contains '"@platforms//cpu:${BAZEL_CPU}"'
assert_contains '"--platforms=//:linux_${BAZEL_CPU}"'
assert_contains '"--extra_toolchains=//:local_config_cc_linux_${BAZEL_CPU}"'
assert_contains '"--host_crosstool_top=@bazel_tools//tools/cpp:toolchain"'
assert_contains '"--repo_env=BAZEL_TARGET_CPU=${BAZEL_CPU}"'

if grep -Fq -- '"--crosstool_top=@local_config_cc//:toolchain"' "${BUILD_SCRIPT}"; then
    echo "Legacy --crosstool_top configuration must not be used." >&2
    exit 1
fi
