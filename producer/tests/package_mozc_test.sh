#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd -P)"
PACKAGE_SCRIPT="${REPO_ROOT}/producer/tools/package_mozc.sh"
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/scarlet-package-mozc.XXXXXX")"
trap 'rm -rf "${TEST_DIR}"' EXIT

if ! tar --version 2>/dev/null | grep -q 'GNU tar'; then
    printf '%s\n' 'package_mozc_test: SKIP (GNU tar required)'
    exit 0
fi

FAKE_BIN_DIR="${TEST_DIR}/bin"
BUILDROOT_DIR="${TEST_DIR}/buildroot-aarch64"
PREBUILT_DIR="${TEST_DIR}/prebuilt"
ARTIFACT_DIR="${TEST_DIR}/artifacts"
mkdir -p "${FAKE_BIN_DIR}" \
    "${BUILDROOT_DIR}/output/host/bin" \
    "${PREBUILT_DIR}/aarch64/root/usr/lib/mozc" \
    "${ARTIFACT_DIR}"

cat > "${FAKE_BIN_DIR}/zstd" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
output=''
while [[ $# -gt 0 ]]; do
    if [[ "$1" == '-o' ]]; then
        output="$2"
        shift 2
    else
        shift
    fi
done
[[ -n "${output}" ]]
cat > "${output}"
EOF
chmod +x "${FAKE_BIN_DIR}/zstd"
ln -s "${FAKE_BIN_DIR}/zstd" "${BUILDROOT_DIR}/output/host/bin/zstd"
printf '%s\n' 'fixture-mozc' > "${PREBUILT_DIR}/aarch64/root/usr/lib/mozc/mozc_server"
chmod +x "${PREBUILT_DIR}/aarch64/root/usr/lib/mozc/mozc_server"

PATH="${FAKE_BIN_DIR}:${PATH}" \
ARCH=aarch64 \
BUILDROOT_DIR="${BUILDROOT_DIR}" \
PREBUILT_DIR="${PREBUILT_DIR}" \
ARTIFACT_DIR="${ARTIFACT_DIR}" \
bash "${PACKAGE_SCRIPT}"

test -s "${ARTIFACT_DIR}/mozc-aarch64.tar.zst"
tar -tf "${ARTIFACT_DIR}/mozc-aarch64.tar.zst" | grep -Fx './usr/lib/mozc/mozc_server'
extract_dir="${TEST_DIR}/extracted"
mkdir -p "${extract_dir}"
tar -xf "${ARTIFACT_DIR}/mozc-aarch64.tar.zst" -C "${extract_dir}" --strip-components=1
test -x "${extract_dir}/usr/lib/mozc/mozc_server"
printf '%s\n' 'package_mozc_test: PASS'
