# Attribution

This repository produces Linux userspace artifacts for the
[Scarlet](https://github.com/petitstrawberry/Scarlet) operating system.
Source packages are built via [Buildroot](https://buildroot.org/) and
optional user-space programs from upstream projects.

## License

The producer scripts and Buildroot configuration in this repository are
licensed under the GNU General Public License v2. See [LICENSE](LICENSE).

Each produced binary retains the license of its upstream source. Release
archives are accompanied by a `legal-info-<arch>.tar.zst` bundle produced
via `make legal-info` that contains:

- Source tarballs
- Patch files
- License texts
- Notice files
- Build configuration

## Release artifacts

For each `vX.Y.Z` release and each `nightly-YYYYMMDD` snapshot, the
following per-arch artifacts are published on GitHub Releases:

- `rootfs-<arch>-vX.Y.Z.tar.zst` - Buildroot rootfs + config overlay
- `apps-demo-<arch>-vX.Y.Z.tar.zst` - optional demo programs
- `mozc-<arch>-vX.Y.Z.tar.zst` - Mozc server assets
- `kvmtool-<arch>-vX.Y.Z.tar.zst` - kvmtool (riscv64 only)
- `shv-guest-<arch>-vX.Y.Z.tar.zst` - SHV guest kernel + initramfs

Redistributable status is reviewed before each stable release. Assets
whose license status cannot be verified (firmware blobs, vendor
libraries, certain fonts/dictionaries) are excluded until cleared.

## Excluded upstream components

The following are NOT redistributed through this repository until their
redistribution terms are confirmed:

- Vendor firmware blobs
- Font packages with non-redistributable clauses
- Dictionaries under unclear licensing
- PDF rendering backends with ambiguous GPL/classpath interaction
