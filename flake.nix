{
  description = "A very basic flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
    in {
      packages.x86_64-linux.default = pkgs.stdenv.mkDerivation {
        nativeBuildInputs = [
          pkgs.binutils
          pkgs.zig
        ];

        pname = "thwomp";
        version = "0.1.0";
        src = ./.;

        buildPhase = ''
            export ZIG_GLOBAL_CACHE_DIR=$TMPDIR/zig-cache
            zig build
          '';

        installPhase = ''
            mkdir -p $out/bin
            cp zig-out/bin/* $out/bin/
          '';
      };

      devShells.x86_64-linux.default = pkgs.mkShell {
        buildInputs = [
          pkgs.binutils
          pkgs.zig
          pkgs.zls
          pkgs.postgresql
        ];
      };
  };
}
