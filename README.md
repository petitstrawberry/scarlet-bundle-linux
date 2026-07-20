# scarlet-bundle-linux

Producer repository for the Linux userspace artifacts consumed by the
[Scarlet](https://github.com/petitstrawberry/Scarlet) operating system.

This repository hosts the Buildroot configuration, build scripts, and
runtime bundle manifests used to generate per-arch Linux root filesystems
and auxiliary user-space artifacts (Mozc, kvmtool, demo applications, SHV
guest kernel/initramfs) for Scarlet.

## License

GPL-2.0-only. See [LICENSE](LICENSE) and [ATTRIBUTION.md](ATTRIBUTION.md)
for the per-package license tracking policy.

## Repository layout

```
scarlet-bundle-linux/
├── producer/                       # build-time only (not consumed by Scarlet users)
│   ├── flake.nix                   # Nix toolchain pin (Buildroot 2025.02.6)
│   ├── tools/                      # build scripts
│   │   ├── prepare.sh              # orchestrator
│   │   ├── build_buildroot.sh
│   │   ├── build_user_programs.sh  # zathura / green / fbdoom
│   │   ├── build_mozc_server.sh
│   │   ├── build_kvmtool.sh        # riscv64 only
│   │   ├── build_guest_image.sh
│   │   ├── build_guest_kernel.sh
│   │   └── deploy_rootfs.sh
│   ├── tests/
│   │   └── deploy_rootfs_test.sh
│   ├── buildroot/                  # Buildroot configs and patches
│   ├── legal-info/                 # license collection automation (Step 7)
│   └── output/                     # local deploy target (gitignored payloads)
│       └── rootfs/{system,data}/linux-{arch}/
├── bundles/                        # runtime contract consumed by Scarlet
│   ├── rootfs/                     # Buildroot rootfs + config
│   │   └── bundle.toml
│   ├── apps-demo/                  # zathura / green / fbdoom overlay
│   │   └── bundle.toml
│   ├── mozc/                       # Mozc server assets
│   │   └── bundle.toml
│   ├── kvmtool/                    # kvmtool (riscv64 only)
│   │   └── bundle.toml
│   └── shv-guest/                  # SHV guest kernel + initramfs
│       └── bundle.toml
├── releases/                       # release manifest templates (Step 5)
└── .github/workflows/              # CI / release automation (Step 5+)
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
tag. Daily snapshots roll under a separate `nightly` tag. See
[ATTRIBUTION.md](ATTRIBUTION.md) for the per-artifact license review policy.

## Relationship to Scarlet

Scarlet consumes bundles from this repository via `cargo-scarlet`. Every
bundle uses `kind = "archive"` layers pinned by URL and SHA-256 against
assets published on GitHub Releases, so clean Scarlet clones no longer
need to run Buildroot. The per-arch SHA-256 map lets a single `bundle.toml`
cover both `aarch64` and `riscv64`:

```toml
[[layers]]
kind = "archive"
url = "https://github.com/petitstrawberry/scarlet-bundle-linux/releases/download/v0.1.0/rootfs-{arch}-v0.1.0.tar.zst"
sha256 = { aarch64 = "sha256:...", riscv64 = "sha256:..." }
format = "tar-zst"
strip_components = 1
to = "/system/linux-{arch}"
```

The `sha256` placeholders in the current manifests are TODO markers. They
will be populated with real hashes when `v0.1.0` is cut (Step 5).

## Status

History extracted from Scarlet's `bundles/linux` (and its former
`tools/linux` location) via `git filter-repo`. Producer environment is
pinned via `producer/flake.nix` (Buildroot 2025.02.6 + nixpkgs). Archive-
kind bundle manifests are in place pending the first release. Release
pipeline, nightly automation, and legal-info collection remain as follow-
up steps.
