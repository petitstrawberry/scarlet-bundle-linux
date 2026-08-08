#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd -P)"
PACKAGE_SCRIPT="${REPO_ROOT}/producer/tools/package_apps_demo.sh"
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/scarlet-package-apps-demo.XXXXXX")"
trap 'rm -rf "${TEST_DIR}"' EXIT

if ! tar --version 2>/dev/null | grep -q 'GNU tar'; then
    printf '%s\n' 'package_apps_demo_test: SKIP (GNU tar required)'
    exit 0
fi

FAKE_BIN_DIR="${TEST_DIR}/bin"
BUILDROOT_DIR="${TEST_DIR}/buildroot-aarch64"
PREBUILT_DIR="${TEST_DIR}/prebuilt"
ARTIFACT_DIR="${TEST_DIR}/artifacts"
mkdir -p "${FAKE_BIN_DIR}" \
    "${BUILDROOT_DIR}/output/host/bin" \
    "${PREBUILT_DIR}/aarch64/bin" \
    "${PREBUILT_DIR}/aarch64/lib/zathura" \
    "${PREBUILT_DIR}/aarch64/share/xkb/rules" \
    "${PREBUILT_DIR}/riscv64/bin" \
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

printf '%s\n' 'fixture-zathura' > "${PREBUILT_DIR}/aarch64/bin/zathura"
printf '%s\n' 'fixture-green' > "${PREBUILT_DIR}/aarch64/bin/green"
printf '%s\n' 'fixture-fbdoom' > "${PREBUILT_DIR}/aarch64/bin/fbdoom"
printf '%s\n' 'fixture-lkvm' > "${PREBUILT_DIR}/aarch64/bin/lkvm"
printf '%s\n' 'fixture-guest-kernel' > "${PREBUILT_DIR}/aarch64/bin/guest-Image"
printf '%s\n' 'fixture-guest-initramfs' > "${PREBUILT_DIR}/aarch64/bin/guest-initramfs.cpio.gz"
printf '%s\n' 'fixture-plugin' > "${PREBUILT_DIR}/aarch64/lib/zathura/libzathura-pdf-poppler.so"
printf '%s\n' 'fixture-xkb' > "${PREBUILT_DIR}/aarch64/share/xkb/rules/base"
chmod +x "${PREBUILT_DIR}/aarch64/bin/zathura"

PATH="${FAKE_BIN_DIR}:${PATH}" \
ARCH=aarch64 \
BUILDROOT_DIR="${BUILDROOT_DIR}" \
PREBUILT_DIR="${PREBUILT_DIR}" \
ARTIFACT_DIR="${ARTIFACT_DIR}" \
bash "${PACKAGE_SCRIPT}"

test -s "${ARTIFACT_DIR}/apps-demo-aarch64.tar.zst"
archive_entries="$(tar -tf "${ARTIFACT_DIR}/apps-demo-aarch64.tar.zst")"
for expected in \
    './usr/bin/zathura' \
    './usr/bin/green' \
    './usr/bin/fbdoom' \
    './usr/bin/lkvm' \
    './usr/lib/zathura/libzathura-pdf-poppler.so' \
    './usr/share/xkb/rules/base'; do
    if ! grep -Fxq -- "${expected}" <<<"${archive_entries}"; then
        echo "apps-demo archive is missing expected entry: ${expected}" >&2
        exit 1
    fi
done
for excluded in 'guest-Image' 'guest-initramfs.cpio.gz'; do
    if grep -Fq -- "${excluded}" <<<"${archive_entries}"; then
        echo "apps-demo archive unexpectedly contains shv-guest artifact: ${excluded}" >&2
        exit 1
    fi
done

extract_dir="${TEST_DIR}/extracted"
mkdir -p "${extract_dir}"
tar -xf "${ARTIFACT_DIR}/apps-demo-aarch64.tar.zst" -C "${extract_dir}" --strip-components=1
test -x "${extract_dir}/usr/bin/zathura"

# riscv64 run: green/fbdoom/lkvm only (zathura stack is aarch64-only today).
printf '%s\n' 'fixture-green-riscv' > "${PREBUILT_DIR}/riscv64/bin/green"
printf '%s\n' 'fixture-lkvm-riscv' > "${PREBUILT_DIR}/riscv64/bin/lkvm"
PATH="${FAKE_BIN_DIR}:${PATH}" \
ARCH=riscv64 \
BUILDROOT_DIR="${TEST_DIR}/buildroot-aarch64" \
PREBUILT_DIR="${PREBUILT_DIR}" \
ARTIFACT_DIR="${ARTIFACT_DIR}" \
bash "${PACKAGE_SCRIPT}"
test -s "${ARTIFACT_DIR}/apps-demo-riscv64.tar.zst"
tar -tf "${ARTIFACT_DIR}/apps-demo-riscv64.tar.zst" | grep -Fxq './usr/bin/lkvm'

# Empty staging must fail loudly.
EMPTY_PREBUILT="${TEST_DIR}/empty-prebuilt"
mkdir -p "${EMPTY_PREBUILT}/aarch64"
if PATH="${FAKE_BIN_DIR}:${PATH}" \
    ARCH=aarch64 \
    BUILDROOT_DIR="${BUILDROOT_DIR}" \
    PREBUILT_DIR="${EMPTY_PREBUILT}" \
    ARTIFACT_DIR="${ARTIFACT_DIR}" \
    bash "${PACKAGE_SCRIPT}" >/dev/null 2>&1; then
    echo "package_apps_demo: empty staging unexpectedly succeeded" >&2
    exit 1
fi

printf '%s\n' 'package_apps_demo_test: PASS'
