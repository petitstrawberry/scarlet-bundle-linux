{
  description = "scarlet-bundle-linux producer environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    buildroot-nix = {
      url = "github:velentr/buildroot.nix/a9090cd64ce2b595a68b2acf2f13463b75673d80";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    buildroot = {
      url = "gitlab:buildroot.org/buildroot/2025.02.6";
      flake = false;
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      buildroot-nix,
      buildroot,
    }:
    let
      system = "x86_64-linux";
      buildrootVersion = "2025.02.6";
      pkgs = nixpkgs.legacyPackages.${system};
      buildrootSource = pkgs.applyPatches {
        name = "buildroot-${buildrootVersion}-scarlet";
        src = buildroot;
        patches = [
          ./buildroot/patches/0001-exclude-listmount-statmount-for-musl.patch
          ./buildroot/patches/0002-libxml-parser-perl-set-runtime-library-path.patch
          ./buildroot/patches/0003-intltool-set-perl-module-path.patch
        ];
      };
      mkBuildroot =
        {
          arch,
          defconfig,
          lockfile,
        }:
        buildroot-nix.lib.mkBuildroot {
          name = "scarlet-bundle-linux-rootfs-${arch}";
          inherit pkgs;
          src = buildrootSource;
          inherit defconfig lockfile;
          nativeBuildInputs = [ pkgs.git ];
        };
      riscv64Buildroot = mkBuildroot {
        arch = "riscv64";
        defconfig = ./buildroot/configs/scarlet_riscv64_defconfig;
        lockfile = ./buildroot/locks/riscv64.json;
      };
      aarch64Buildroot = mkBuildroot {
        arch = "aarch64";
        defconfig = ./buildroot/configs/scarlet_aarch64_defconfig;
        lockfile = ./buildroot/locks/aarch64.json;
      };
      mkRootfs =
        {
          arch,
          buildrootPackage,
        }:
        pkgs.runCommand "scarlet-bundle-linux-rootfs-${arch}-archive"
          {
            nativeBuildInputs = [ pkgs.zstd ];
          }
          ''
            mkdir -p "$out"
            cp "${buildrootPackage.buildroot}/images/rootfs.tar" "$out/rootfs-${arch}.tar"
            zstd -19 "$out/rootfs-${arch}.tar" -o "$out/rootfs-${arch}.tar.zst"
          '';
      rootfsRiscv64 = mkRootfs {
        arch = "riscv64";
        buildrootPackage = riscv64Buildroot;
      };
      rootfsAarch64 = mkRootfs {
        arch = "aarch64";
        buildrootPackage = aarch64Buildroot;
      };
    in
    {
      devShells.${system}.default = pkgs.mkShell {
        SCARLET_BUNDLE_BUILDROOT_VERSION = buildrootVersion;
        SCARLET_BUNDLE_BUILDROOT_SOURCE = "${buildrootSource}";
      };
      packages.${system} = {
        lock-riscv64 = riscv64Buildroot.packageLockFile;
        lock-aarch64 = aarch64Buildroot.packageLockFile;
        rootfs-riscv64 = rootfsRiscv64;
        rootfs-aarch64 = rootfsAarch64;
        default = rootfsRiscv64;
      };
    };
}
