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

        # Build wasm-bindgen-cli 0.2.106 (matching Cargo.lock)
        # Based on nixpkgs wasm-bindgen-cli_0_2_105, updated to 0.2.106
        wasm-bindgen-cli = pkgs.buildWasmBindgenCli rec {
          src = pkgs.fetchCrate {
            pname = "wasm-bindgen-cli";
            version = "0.2.106";
            hash = "sha256-M6WuGl7EruNopHZbqBpucu4RWz44/MSdv6f0zkYw+44=";
          };
          cargoDeps = pkgs.rustPlatform.fetchCargoVendor {
            inherit src;
            inherit (src) pname version;
            hash = "sha256-ElDatyOwdKwHg3bNH/1pcxKI7LXkhsotlDPQjiLHBwA=";
          };
        };

        # Build the WASM modules required by the frontend
        wasmModules = pkgs.rustPlatform.buildRustPackage {
          pname = "rauthy-wasm-modules";
          version = "0.33.2";
          src = ./.;

          cargoLock = {
            lockFile = ./Cargo.lock;
          };

          nativeBuildInputs = with pkgs; [
            wasm-bindgen-cli
            binaryen
            lld
          ];

          buildPhase = ''
            runHook preBuild

            mkdir -p $out/spow $out/md

            # Build and process spow WASM
            cargo build --release --target wasm32-unknown-unknown \
              -p rauthy-wasm-modules --features spow
            wasm-bindgen --target web --out-dir $out/spow --out-name spow \
              target/wasm32-unknown-unknown/release/wasm.wasm
            wasm-opt -O --enable-bulk-memory --enable-nontrapping-float-to-int --enable-sign-ext --enable-mutable-globals $out/spow/spow_bg.wasm -o $out/spow/spow_bg.wasm

            # Build and process md WASM
            cargo build --release --target wasm32-unknown-unknown \
              -p rauthy-wasm-modules --features md
            wasm-bindgen --target web --out-dir $out/md --out-name md \
              target/wasm32-unknown-unknown/release/wasm.wasm
            wasm-opt -O --enable-bulk-memory --enable-nontrapping-float-to-int --enable-sign-ext --enable-mutable-globals $out/md/md_bg.wasm -o $out/md/md_bg.wasm

            runHook postBuild
          '';

          installPhase = ''
            runHook preInstall
            # Output already created in buildPhase
            runHook postInstall
          '';

          doCheck = false;
        };

        frontend = pkgs.buildNpmPackage {
          pname = "rauthy-frontend";
          version = "0.33.2";
          src = ./frontend;

          patches = [
            ./nix/0001-build-svelte-files-inside-the-current-directory.patch
          ];

          patchFlags = [ "-p2" ];

          npmDepsHash = "sha256-nOxsOdJG5iz8bW6Ogyzk/2RB+lMF5yJD47p8StZ/Vvg=";

          preBuild = ''
            mkdir -p src/wasm
            cp -r ${wasmModules}/spow src/wasm/
            cp -r ${wasmModules}/md src/wasm/
          '';

          installPhase = ''
            runHook preInstall
            mkdir -p $out
            cp -r dist/* $out/
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
            cp -r ${frontend}/templates/html/ templates/html
            cp -r ${frontend}/static/ static
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
          inherit rauthy frontend wasmModules;
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
