{
  description = "Rauthy - Single Sign-On Identity & Access Management";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};

        frontend = pkgs.buildNpmPackage {
          pname = "rauthy-frontend";
          version = "0.33.2";
          src = ./frontend;

          patches = [
            ./nix/0001-build-svelte-files-inside-the-current-directory.patch
          ];

          patchFlags = [ "-p2" ];

          npmDepsHash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";

          installPhase = ''
            runHook preInstall
            mkdir -p $out/lib/node_modules/frontend/dist
            cp -r dist/* $out/lib/node_modules/frontend/dist/
            runHook postInstall
          '';
        };

        rauthy = pkgs.rustPlatform.buildRustPackage {
          pname = "rauthy";
          version = "0.33.2";
          src = ./.;

          cargoLock = {
            lockFile = ./Cargo.lock;
          };

          nativeBuildInputs = with pkgs; [
            pkg-config
            perl
            rustPlatform.bindgenHook
            jemalloc
          ];

          buildInputs = with pkgs; [
            openssl
          ];

          preBuild = ''
            cp -r ${frontend}/lib/node_modules/frontend/dist/templates/html/ templates/html
            cp -r ${frontend}/lib/node_modules/frontend/dist/static/ static
          '';

          doCheck = false;

          meta = with pkgs.lib; {
            description = "Single Sign-On Identity & Access Management via OpenID Connect, OAuth 2.0 and PAM";
            homepage = "https://github.com/sebadob/rauthy";
            changelog = "https://github.com/sebadob/rauthy/releases/tag/v0.33.2";
            license = licenses.asl20;
            mainProgram = "rauthy";
            platforms = platforms.linux;
          };
        };
      in
      {
        packages = {
          inherit rauthy frontend;
          default = rauthy;
        };

        devShells.default = pkgs.mkShell {
          inputsFrom = [ rauthy ];
          packages = with pkgs; [
            cargo
            rustc
            rust-analyzer
            clippy
            rustfmt
            nodejs
          ];
        };
      }
    );
}