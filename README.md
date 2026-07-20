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
│   ├── flake.nix                   # Nix toolchain pin (placeholder; Step 3)
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
│   ├── buildroot/                  # Buildroot configs and patches (Step 3)
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

Scarlet consumes bundles from this repository via `cargo-scarlet`. The
rootfs bundle currently uses `kind = "copy"` layers against the locally
deployed tree under `producer/output/`. The migration plan switches every
bundle to `kind = "archive"` layers pointing at GitHub Releases URLs, so
clean Scarlet clones no longer need to run Buildroot.

## Status

History extracted from Scarlet's `bundles/linux` (and its former
`tools/linux` location) via `git filter-repo`. Producer flake, Buildroot
configs, release pipeline, and the archive-kind bundle manifests will
land as follow-up commits.
