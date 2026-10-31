{
  description = "Temporion x86 — CPU (Tctl), NVIDIA GPU and NVMe temperatures in the GNOME top bar";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    systems.url = "github:nix-systems/default-linux";
  };

  outputs =
    { self, nixpkgs, systems, ... }:
    let
      uuid = "temporion-x86@masterzack69";
      eachSystem = nixpkgs.lib.genAttrs (builtins.filter (system: system == "x86_64-linux") (import systems));
      pkgsFor = system: import nixpkgs { inherit system; };
    in
    {
      packages = eachSystem (
        system:
        let
          pkgs = pkgsFor system;

          # Native x86-64 assembly daemon. Rust remains as a reference baseline.
          temporion-x86d = pkgs.stdenv.mkDerivation {
            pname = "temporion-x86d";
            version = "0.2.0";
            src = ./.;
            nativeBuildInputs = [ pkgs.python3 ];
            dontConfigure = true;
            doCheck = true;
            checkPhase = "make test";
            installPhase = ''
              runHook preInstall
              make install PREFIX="$out"
              runHook postInstall
            '';
            meta = {
              description = "x86-64 assembly daemon streaming CPU/GPU/NVMe temperatures";
              homepage = "https://github.com/MasterZack69/temporion-x86";
              license = pkgs.lib.licenses.agpl3Only;
              platforms = [ "x86_64-linux" ];
              mainProgram = "temporion-x86d";
            };
          };

          # The GNOME extension: a thin GJS reader with the daemon's absolute
          # store path baked in, installed to the standard extensions dir.
          temporion-x86 = pkgs.stdenvNoCC.mkDerivation {
            pname = "temporion-x86-gnome-extension";
            version = "0.1.0";
            src = ./.;
            dontConfigure = true;
            dontBuild = true;
            installPhase = ''
              runHook preInstall
              dir="$out/share/gnome-shell/extensions/${uuid}"
              mkdir -p "$dir"
              cp -r extension/. "$dir"/
              substituteInPlace "$dir/extension.js" \
                --replace-fail '@TEMPORION_X86D@' '${temporion-x86d}/bin/temporion-x86d'
              runHook postInstall
            '';
            passthru = {
              extensionUuid = uuid;
              inherit temporion-x86d;
            };
            meta = {
              description = "Temporion x86 GNOME Shell extension (frontend for temporion-x86d)";
              homepage = "https://github.com/MasterZack69/temporion-x86";
              license = pkgs.lib.licenses.agpl3Only;
              platforms = [ "x86_64-linux" ];
            };
          };
        in
        {
          inherit temporion-x86d temporion-x86;
          default = temporion-x86;
        }
      );

      # `nix run` runs the daemon standalone (handy for verifying sensors).
      apps = eachSystem (system: {
        default = {
          type = "app";
          program = "${self.packages.${system}.temporion-x86d}/bin/temporion-x86d";
        };
      });

      checks = eachSystem (system: {
        inherit (self.packages.${system}) temporion-x86d temporion-x86;
      });

      formatter = eachSystem (system: (pkgsFor system).nixpkgs-fmt);

      devShells = eachSystem (
        system:
        let
          pkgs = pkgsFor system;
        in
        {
          default = pkgs.mkShell {
            packages = with pkgs; [
              gnumake
              gcc
              python3
              cargo
              rustc
              rustfmt
              clippy
              gjs
              nodejs
            ];
          };
        }
      );
    };
}
