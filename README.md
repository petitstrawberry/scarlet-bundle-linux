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
├── tools/                          # build scripts (Buildroot, user programs, mozc, kvmtool, guest)
│   ├── prepare.sh                  # orchestrator
│   ├── build_buildroot.sh
│   ├── build_user_programs.sh
│   ├── build_mozc_server.sh
│   ├── build_kvmtool.sh
│   ├── build_guest_image.sh
│   ├── build_guest_kernel.sh
│   └── deploy_rootfs.sh
├── tests/
│   └── deploy_rootfs_test.sh
├── rootfs/                         # deployed tree (binaries ignored, sentinels tracked)
│   ├── system/linux-{arch}/
│   └── data/config/linux-{arch}/
├── bundle.toml                     # runtime bundle (currently local-copy kind; archive-kind migration pending)
└── README.md
```

Build artifacts (`cache/`, `prebuilt/`, generated rootfs payloads) are kept
out of git. The producer environment will be pinned via a Nix flake in a
follow-up commit.

## Relationship to Scarlet

Scarlet consumes this repository via `cargo-scarlet`. The current
`bundle.toml` uses `kind = "copy"` layers against a locally deployed
rootfs tree. The migration plan switches this to `kind = "archive"`
layers pointing at GitHub Releases published from this repository, so
that clean Scarlet clones no longer need to run Buildroot themselves.

See the design discussion in the Scarlet repository for details.

## Status

History extracted from Scarlet's `bundles/linux` (and its former
`tools/linux` location) via `git filter-repo`. Initial restructuring is
in progress; producer flake, release pipeline, and archive-kind bundle
manifests will land as follow-up commits.
