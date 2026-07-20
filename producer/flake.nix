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
      forAllSystems = f: nixpkgs.lib.genAttrs supportedSystems (system: f system);

      buildrootVersion = "2025.02.6";

      mkSystem =
        system:
        let
          pkgs = import nixpkgs { inherit system; };

          hostTools =
            [
              pkgs.bashInteractive
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
        in
        {
          devShell = pkgs.mkShell {
            packages = hostTools;
            SCARLET_BUNDLE_BUILDROOT_VERSION = buildrootVersion;
            SCARLET_BUNDLE_BUILDROOT_SOURCE = "${buildroot}";
          };
        };
    in
    {
      devShells = forAllSystems (
        system: {
          default = (mkSystem system).devShell;
        }
      );
    };
}
