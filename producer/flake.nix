{
  description = "scarlet-bundle-linux producer environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    buildroot = {
      url = "gitlab:buildroot.org/buildroot/2025.02.6";
      flake = false;
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      buildroot,
    }:
    let
      supportedSystems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];
      linuxSystems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = f: nixpkgs.lib.genAttrs supportedSystems (system: f system);
      forLinuxSystems = f: nixpkgs.lib.genAttrs linuxSystems (system: f system);

      buildrootVersion = "2025.02.6";

      mkSystem =
        system:
        let
          pkgs = import nixpkgs { inherit system; };

          hostTools =
            [
              pkgs.bashInteractive
              pkgs.cacert
              pkgs.gnumake
              pkgs.git
              pkgs.curl
              pkgs.wget
              pkgs.gnutar
              pkgs.gzip
              pkgs.bzip2
              pkgs.xz
              pkgs.cpio
              pkgs.meson
              pkgs.ninja
              pkgs.python3
              pkgs.rsync
              pkgs.gnused
              pkgs.gnugrep
              pkgs.which
              pkgs.findutils
              pkgs.coreutils
              pkgs.file
              pkgs.patch
              pkgs.perl
              pkgs.unzip
              pkgs.bc
              pkgs.gawk
              pkgs.dtc
              pkgs.util-linux
              pkgs.gcc
              pkgs.pkg-config
              pkgs.autoconf
              pkgs.automake
              pkgs.libtool
              pkgs.cmake
              pkgs.ncurses
              pkgs.openssl
              pkgs.libffi
              pkgs.zlib
            ]
            ++ pkgs.lib.optional pkgs.stdenv.isLinux pkgs.bazelisk
            ++ pkgs.lib.optional (
              pkgs.stdenv.isLinux && pkgs.system == "x86_64-linux"
            ) pkgs.pkgsCross.aarch64-multiplatform.buildPackages.gcc
            ++ pkgs.lib.optional (
              pkgs.stdenv.isLinux && pkgs.system == "x86_64-linux"
            ) pkgs.pkgsCross.riscv64.buildPackages.gcc;

          mkRootfs =
            {
              arch,
              defconfig ? null,
              extraUtilsConfig ? false,
            }:
            pkgs.stdenv.mkDerivation {
              name = "scarlet-bundle-linux-rootfs-${arch}";

              nativeBuildInputs = hostTools;

              # All sources are wired explicitly inside buildPhase (Buildroot via
              # the flake input, scarlet-bundle-linux patches via ${self}). Skip
              # the default unpack/configure phases so stdenv does not look for
              # $src or a ./configure script.
              dontUnpack = true;
              dontConfigure = true;

              BUILDROOT_VERSION = buildrootVersion;
              ARCH = arch;
              SCARLET_BUNDLE_SKIP_HOST_CHECK = "1";
              SSL_CERT_FILE = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
              NIX_SSL_CERT_FILE = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
              CURL_CA_BUNDLE = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";

              outputHashMode = "recursive";
              outputHashAlgo = "sha256";
              outputHash = pkgs.lib.fakeSha256;

              buildPhase = ''
                mkdir -p "$NIX_BUILD_TOP/buildroot"
                cp -r ${buildroot}/. "$NIX_BUILD_TOP/buildroot/"
                chmod -R u+w "$NIX_BUILD_TOP/buildroot"
                patchShebangs "$NIX_BUILD_TOP/buildroot"

                export BUILDROOT_DIR="$NIX_BUILD_TOP/buildroot"
                export PREBUILT_DIR="$NIX_BUILD_TOP/prebuilt"
                export WORKDIR="$NIX_BUILD_TOP/work"
                export MAKE_JOBS="$NIX_BUILD_CORES"
                mkdir -p "$PREBUILT_DIR" "$WORKDIR"

                cd "$BUILDROOT_DIR"
                for p in ${self}/buildroot/patches/*.patch; do
                  echo "Applying $p"
                  patch -p1 < "$p"
                done

                substituteInPlace support/dependencies/dependencies.sh \
                  --replace-fail 'check_prog_host "/usr/bin/file"' 'check_prog_host "file"'

                ${
                  if defconfig != null then
                    ''
                      cp ${self}/buildroot/configs/${defconfig} .config
                      make olddefconfig
                    ''
                  else
                    ''
                      make qemu_aarch64_virt_defconfig
                    ''
                }

                ${pkgs.lib.optionalString extraUtilsConfig ''
                  bash ${self}/buildroot/configs/common_linux_userland.sh
                  make olddefconfig

                  toolchain_gxx="$BUILDROOT_DIR/output/host/bin/aarch64-buildroot-linux-musl-g++"
                  if [[ ! -x "$toolchain_gxx" ]]; then
                    make host-gcc-final-dirclean gcc-final-dirclean
                  fi
                ''}

                make -j"$MAKE_JOBS"

                test -f output/images/rootfs.tar
                mkdir -p "$PREBUILT_DIR/${arch}"
                cp output/images/rootfs.tar "$PREBUILT_DIR/${arch}/rootfs.tar"
              '';

              installPhase = ''
                mkdir -p "$out"
                cp "$PREBUILT_DIR/${arch}/rootfs.tar" "$out/rootfs-${arch}.tar"
                ${pkgs.zstd}/bin/zstd -19 "$out/rootfs-${arch}.tar" -o "$out/rootfs-${arch}.tar.zst"
              '';
            };
        in
        {
          devShell = pkgs.mkShell {
            packages = hostTools;
            SCARLET_BUNDLE_BUILDROOT_VERSION = buildrootVersion;
            SCARLET_BUNDLE_BUILDROOT_SOURCE = "${buildroot}";
          };

          packages = {
            rootfs-riscv64 = mkRootfs {
              arch = "riscv64";
              defconfig = "scarlet_riscv64_defconfig";
            };
            rootfs-aarch64 = mkRootfs {
              arch = "aarch64";
              extraUtilsConfig = true;
            };
          };
        };
    in
    {
      devShells = forAllSystems (
        system: {
          default = (mkSystem system).devShell;
        }
      );
      packages = forLinuxSystems (system: (mkSystem system).packages);

      # Let macOS evaluate the Linux package with `nix build --dry-run .#rootfs-*`.
      rootfs-riscv64 = self.packages.x86_64-linux.rootfs-riscv64;
      rootfs-aarch64 = self.packages.x86_64-linux.rootfs-aarch64;
    };
}
