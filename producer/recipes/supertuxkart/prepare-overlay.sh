#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 5 ]; then
    echo "usage: $0 OUTPUT_DIR STK_PACKAGE_ROOT SDL2_SWS_SO SGFX_ICD_SO SWS_CLIENT_SO" >&2
    exit 2
fi

output=$1
game_root=$2
sdl2=$3
icd=$4
sws=$5
script_dir=$(cd "$(dirname "$0")" && pwd)

if [ -e "$output" ]; then
    echo "output already exists: $output" >&2
    exit 1
fi
for input in "$game_root/usr/bin/supertuxkart" \
    "$game_root/usr/share/supertuxkart" \
    "$game_root/usr/lib/libvulkan.so.1" \
    "$sdl2" "$icd" "$sws"; do
    if [ ! -e "$input" ]; then
        echo "required input is missing: $input" >&2
        exit 1
    fi
done

linux_root="$output/systems/linux-aarch64"
mkdir -p "$linux_root/usr/bin" "$linux_root/usr/lib" \
    "$linux_root/usr/share" "$linux_root/usr/games" \
    "$linux_root/etc/vulkan/icd.d"
cp -p "$game_root/usr/bin/supertuxkart" "$linux_root/usr/bin/"
cp -a "$game_root/usr/lib/." "$linux_root/usr/lib/"
cp -a "$game_root/usr/share/supertuxkart" "$linux_root/usr/share/"
cp -p "$sdl2" "$linux_root/usr/lib/libSDL2-2.0.so.0.sws"
rm -f "$linux_root/usr/lib/libSDL2-2.0.so.0"
ln -s libSDL2-2.0.so.0.sws "$linux_root/usr/lib/libSDL2-2.0.so.0"
cp -p "$icd" "$linux_root/usr/lib/libvulkan_sgfx.so"
cp -p "$sws" "$linux_root/usr/lib/libsws_client_c.so"
cp -p "$script_dir/stk.sh" "$linux_root/usr/games/stk-sgfx.sh"
chmod 755 "$linux_root/usr/games/stk-sgfx.sh"
cat > "$linux_root/etc/vulkan/icd.d/sgfx.json" <<'EOF'
{"file_format_version":"1.0.0","ICD":{"library_path":"/usr/lib/libvulkan_sgfx.so","api_version":"1.0.0"}}
EOF

echo "Prepared test-only overlay: $output"
