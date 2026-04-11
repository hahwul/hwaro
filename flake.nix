{
  description = "A fast, lightweight static site generator built with Crystal";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };

        hwaro = pkgs.crystal.buildCrystalPackage rec {
          pname = "hwaro";
          version = "0.11.1";

          src = ./.;

          shardsFile = ./shards.nix;

          crystalBinaries.hwaro.src = "src/main.cr";

          crystalBinaries.hwaro.options = [ "--release" "--no-debug" ];

          nativeBuildInputs = [ pkgs.crystal pkgs.shards ];
          buildInputs = [ ];

          buildPhase = ''
            runHook preBuild
            shards build --release
            runHook postBuild
          '';

          installPhase = ''
            runHook preInstall
            mkdir -p $out/bin
            cp bin/hwaro $out/bin/hwaro
            runHook postInstall
          '';

          doCheck = false;

          meta = with pkgs.lib; {
            description = "A fast, lightweight static site generator built with Crystal";
            homepage = "https://github.com/hahwul/hwaro";
            license = licenses.mit;
            maintainers = [ "hahwul" ];
            mainProgram = "hwaro";
          };
        };
      in
      {
        packages.default = hwaro;

        devShells.default = pkgs.mkShell {
          inputsFrom = [ hwaro ];
          nativeBuildInputs = with pkgs; [ crystal shards crystal2nix just ];
          shellHook = ''
            echo "hwaro development environment loaded (via Nix)"
            echo "Running shards install..."
            shards install || true
          '';
        };
      });
}
