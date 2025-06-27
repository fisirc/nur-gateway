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
            zig build -Doptimize=ReleaseSafe --global-cache-dir $TMPDIR/zig-cache
          '';

            installPhase = ''
            mkdir -p $out/bin
            cp zig-out/bin/* $out/bin/
          '';

            outputHashAlgo = "sha256";
            outputHashMode = "recursive";
            outputHash = "";
          };
        in
          pkgs.stdenv.mkDerivation {
            pname = "thwomp";
            version = "1.0.0";
            src = ./.;

            nativeBuildInputs = [
              deps
            ];
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
