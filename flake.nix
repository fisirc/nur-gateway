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
      packages.x86_64-linux.default =
        let
          deps = pkgs.stdenv.mkDerivation {
            pname = "thwomp-deps";
            version = "0.0.0";
            src = ./.;

            nativeBuildInputs = [
              pkgs.zig
              pkgs.binutils
            ];

            buildPhase = ''
            mkdir $TMPDIR/zig-cache
            export ZIG_GLOBAL_CACHE_DIR=$TMPDIR/zig-cache
            zig build --fetch
          '';

            installPhase = ''
            mkdir -p $out/cache
            cp -r $TMPDIR/zig-cache $out/cache
          '';

            dontPatchShebangs = true;

            outputHashAlgo = "sha256";
            outputHashMode = "recursive";
            outputHash = "sha256-G8zEUjtypOyS3DdpXXHJDW2r469CDGcHgcf0aDFPMwg=";
          };
        in
          pkgs.stdenv.mkDerivation {
            pname = "thwomp";
            version = "1.0.0";
            src = ./.;

            nativeBuildInputs = [
              pkgs.zig
              pkgs.binutils
            ];

            buildPhase = ''
           export ZIG_GLOBAL_CACHE_DIR=${deps}/cache
           zig build -Doptimize=ReleaseSafe
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
