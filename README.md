# scarlet-bundle-linux

Producer repository for the Linux userspace artifacts consumed by the
[Scarlet](https://github.com/petitstrawberry/Scarlet) operating system.

This repository hosts the Buildroot configuration, build scripts, and runtime
bundle manifests used to generate per-architecture Linux root filesystems and
auxiliary user-space artifacts (Mozc, kvmtool, demo applications, and the SHV
guest kernel/initramfs) for Scarlet.

## Building Buildroot root filesystems

Rootfs builds run directly on a normal Linux host. The release workflow uses
Ubuntu 24.04. The script downloads vanilla Buildroot 2025.02.6, verifies the official
tarball SHA-256 before extraction, applies the retained Buildroot-tree patches
with zero fuzz, and configures the Scarlet BR2_EXTERNAL tree. Buildroot's own
download hash checks are mandatory, and both defconfigs enable Buildroot's
reproducible-build setting.

```bash
# Run on Ubuntu 24.04 or another supported Linux host.
# Build and stage RISC-V rootfs, release rootfs, and legal-info archives.
ARCH=riscv64 bash producer/tools/build_buildroot.sh

# Build AArch64.
ARCH=aarch64 bash producer/tools/build_buildroot.sh

# Validate the pinned source, patches, and generated configuration only.
ARCH=aarch64 BUILDROOT_BUILD_MODE=configure \
  bash producer/tools/build_buildroot.sh
```

Defaults are deliberately per architecture:

```
producer/cache/buildroot-riscv64/output/
producer/cache/buildroot-aarch64/output/
```

`BUILDROOT_DIR` can be set to another per-architecture work directory. Its
`output/host` and `output/staging` paths remain the interface consumed by the
guest kernel, Mozc, kvmtool, and user-program scripts. `BUILDROOT_DL_DIR`
defaults to the shared `producer/cache/buildroot-dl` download cache; Buildroot
handles its own download locking. `PREBUILT_DIR` receives
`<arch>/rootfs.tar`, while `ARTIFACT_DIR` receives
`rootfs-<arch>.tar.zst` and `legal-info-<arch>.tar.zst`.

Full builds use Buildroot's configured host-zstd to create `.zst` artifacts.
The legal-info archive is created from Buildroot's `make legal-info` output
with normalized GNU tar metadata.

## License

GPL-2.0-only. See [LICENSE](LICENSE) and [ATTRIBUTION.md](ATTRIBUTION.md) for
the per-package license tracking policy.

## Repository layout

```
scarlet-bundle-linux/
├── producer/                       # build-time only (not consumed by Scarlet users)
│   ├── buildroot/
│   │   ├── external/                # BR2_EXTERNAL metadata and defconfigs
│   │   └── patches/                 # Buildroot-source recipe patches
│   ├── tools/
│   │   ├── build_buildroot.sh       # direct Linux Buildroot driver
│   │   ├── prepare.sh               # orchestrator
│   │   ├── build_user_programs.sh   # zathura / green / fbdoom
│   │   ├── build_mozc_server.sh
│   │   ├── build_kvmtool.sh         # riscv64 only
│   │   ├── build_guest_image.sh
│   │   ├── build_guest_kernel.sh
│   │   └── deploy_rootfs.sh
│   ├── tests/                       # focused shell tests
│   ├── cache/buildroot-<arch>/      # source + output/ work directories
│   ├── cache/buildroot-dl/          # shared Buildroot download cache
│   ├── prebuilt/<arch>/rootfs.tar   # downstream staging contract
│   └── artifacts/                   # rootfs + legal-info release archives
├── bundles/                         # runtime contract consumed by Scarlet
├── releases/                        # release manifest templates
└── .github/workflows/               # CI / release automation
```

## Bundle lifecycle split

| Bundle | Artifact | Updates when |
|---|---|---|
| `rootfs` | Buildroot minimal rootfs + config | Buildroot bump, base package set change |
| `apps-demo` | zathura / green / fbdoom binaries | demo app upstream change |
| `mozc` | Mozc server + dictionary | Mozc upstream change |
| `kvmtool` | kvmtool (riscv64 only) | kvmtool upstream change |
| `shv-guest` | guest kernel + initramfs for nested virt | guest kernel bump or rootfs refresh |

All artifacts for a given `vX.Y.Z` are attached to a single GitHub Release
tag. Daily validation builds are retained temporarily as GitHub Actions
artifacts and do not create a release tag. See
[ATTRIBUTION.md](ATTRIBUTION.md) for the per-artifact license review policy.

## Relationship to Scarlet

Scarlet consumes bundles from this repository via `cargo-scarlet`. Every
bundle uses `kind = "archive"` layers pinned by URL and SHA-256 against assets
published on GitHub Releases, so clean Scarlet clones do not need to run
Buildroot. The per-architecture SHA-256 map lets a single `bundle.toml` cover
both `aarch64` and `riscv64`:

```toml
[[layers]]
kind = "archive"
url = "https://github.com/petitstrawberry/scarlet-bundle-linux/releases/download/v0.1.0/rootfs-{arch}-v0.1.0.tar.zst"
sha256 = { aarch64 = "sha256:...", riscv64 = "sha256:..." }
format = "tar-zst"
strip_components = 1
to = "/system/linux-{arch}"
```

The rootfs and Mozc hashes are populated from the published `v0.1.0` release.
The apps-demo, kvmtool, and shv-guest manifests remain TODO until those
bundles are included in a release.

## Cutting a release

1. Open the **Build release** workflow and run it with a version such as
   `v0.1.0`. It builds both architectures directly on Ubuntu 24.04, restores a
   per-architecture Buildroot download cache, and verifies the official
   Buildroot source tarball before each extraction.
2. Leave `publish` disabled for build-only validation. The workflow still
   builds and uploads each versioned rootfs, legal-info, and pinned Mozc archive plus
   the `manifest-<arch>.toml` fragment. Enable `publish` only to attach all of
   those files to a draft GitHub Release.
3. Each manifest contains the rootfs release URL and its `sha256:<hex>` value.
   Use it to replace the matching TODO in `bundles/rootfs/bundle.toml` as a
   separate release update.

## Nightly validation

The **Nightly Buildroot validation** workflow runs daily at 03:15 UTC and can
also be started manually. It builds both architectures directly on Ubuntu
24.04, but does not create a GitHub Release or modify the stable bundle
manifests. The rootfs, legal-info, and build metadata are uploaded as Actions
artifacts for 14 days. Stable releases remain an explicit manual operation.

For a local build, use the Linux commands above. Use
`scripts/compute-artifact-hash.sh <file>` to format any artifact hash for a
cargo-scarlet manifest.
