{
  description = "A very basic flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
      deps = pkgs.callPackage ./build.zig.zon.nix {};
    in {
      packages.x86_64-linux.default = pkgs.stdenv.mkDerivation {
        pname = "thwomp";
        version = "1.0.0";
        src = ./.;

        nativeBuildInputs = [
          pkgs.zig
          pkgs.binutils
        ];

        buildPhase = ''
            mkdir -p $TMPDIR/cache
            cp -r ${deps}/* $TMPDIR/cache

            export ZIG_GLOBAL_CACHE_DIR=$TMPDIR/cache
            chmod --recursive +w $ZIG_GLOBAL_CACHE_DIR

            ls -la $TMPDIR/cache

            zig build -Doptimize=ReleaseSafe --system $ZIG_GLOBAL_CACHE_DIR
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
