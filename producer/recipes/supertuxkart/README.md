# SuperTuxKart 1.5 on Scarlet VirGL

The game itself needs no Scarlet patch. The 2026-09-18 check ran the unmodified
Alpine AArch64 `supertuxkart` and `supertuxkart-data` 1.5-r1 packages. This
directory holds only the private-image staging script, launcher, and tested
steps. No game binary or assets are committed to this repository.

The runtime path is STK → the distribution's Khronos `libvulkan.so.1` → the
normal ICD manifest → `libvulkan_sgfx.so` → Scarlet VirGL. The separate
[SDL2 SWS port](https://github.com/petitstrawberry/sdl2-sws)
provides the fullscreen window and input through `VK_KHR_display`. SGFX and
the SWS C client come from [Scarlet's Vulkan setup](https://github.com/petitstrawberry/Scarlet/blob/feature/vulkan/docs/graphics/vulkan-games.md).

Prepare the game package tree outside Git. The tested package setup first
installed Alpine 3.22 dependencies, then selected the 1.5-r1 game and data
packages from edge:

```sh
export STK_WORK=/private/tmp/scarlet-stk-test
mkdir -p "$STK_WORK/package/etc/apk"
docker run --rm --platform linux/arm64 -v "$STK_WORK/package:/game" alpine:3.22 sh -ec '
  cp -a /etc/apk/keys /game/etc/apk/
  apk add --no-cache --root /game --initdb \
    -X https://dl-cdn.alpinelinux.org/alpine/v3.22/main \
    -X https://dl-cdn.alpinelinux.org/alpine/v3.22/community \
    supertuxkart vulkan-loader
  apk add --no-cache --root /game \
    -X https://dl-cdn.alpinelinux.org/alpine/edge/main \
    -X https://dl-cdn.alpinelinux.org/alpine/edge/community \
    supertuxkart=1.5-r1 supertuxkart-data=1.5-r1
'
```

Build release `libsws_client_c.so` and the Linux/musl `vulkan-sgfx` ICD for
AArch64 using the Scarlet/SGFX source revisions pinned by the image. Build
SDL2 2.32.10 from the separate SWS port, passing those C client artifacts:

```sh
export SWS_LIB_DIR=/path/to/directory/containing/libsws_client_c.so
export SDL_SWS_REPO=/path/to/sdl2-sws
export SCARLET_REPO=/path/to/Scarlet
docker run --rm --platform linux/arm64 \
  -v "$SCARLET_REPO:/scarlet:ro" -v "$STK_WORK:/work" \
  -v "$SWS_LIB_DIR:/sws:ro" -v "$SDL_SWS_REPO:/port:ro" \
  alpine:3.22 sh -ec '
    apk add --no-cache build-base cmake ninja curl patch linux-headers
    make -C /port WORK_DIR=/work/sdl-build \
      SWS_CLIENT_INCLUDE_DIR=/scarlet/user/lib/sws-client-c/include \
      SWS_CLIENT_LIBRARY=/sws/libsws_client_c.so JOBS=8
  '
```

The resulting library is
`$STK_WORK/sdl-build/release/libSDL2-2.0.so.0.3200.10`.

From this repository's root, create a test overlay with the packages, patched SDL2,
release ICD, and release SWS client:

```sh
producer/recipes/supertuxkart/prepare-overlay.sh \
  "$STK_WORK/overlay" "$STK_WORK/package" \
  "$STK_WORK/sdl-build/release/libSDL2-2.0.so.0.3200.10" \
  /path/to/libvulkan_sgfx.so /path/to/libsws_client_c.so
```

For a private Scarlet full image, temporarily add this layer after the normal
rootfs layers in `projects/aarch64-limine-full/scarlet.toml`:

```toml
[[images.rootfs.layers]]
kind = "copy"
source = "/private/tmp/scarlet-stk-test/overlay"
to = "/"
```

From the Scarlet repository root, build and launch:

```sh
cargo scarlet image --release --project projects/aarch64-limine-full
SCARLET_QEMU_ACCEL=hvf SCARLET_QEMU_SNAPSHOT=1 \
  projects/aarch64-limine-full/tools/run_aarch64.sh
```

Restore the manifest and rebuild the ordinary image after the test; do not commit the temporary layer
or game payload.

At the Scarlet serial shell:

```sh
abi-run linux-aarch64 /bin/sh /usr/games/stk-sgfx.sh
```

The launcher selects the ordinary ICD with `VK_DRIVER_FILES` and SDL's SWS
driver. The tested run logged `Vulkan renderer: SGFX Vulkan (Scarlet VirGL GPU 0)`,
rendered, and was playable. Audio output and every asset path were not
verified. STK 1.5 did not accept `--resolution=1280x800`; use the current SWS
display mode instead.
