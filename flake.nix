{
  description = "Temporion — CPU (Tctl), NVIDIA GPU and NVMe temperatures in the GNOME top bar";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    systems.url = "github:nix-systems/default-linux";
  };

  outputs =
    { self, nixpkgs, systems, ... }:
    let
      uuid = "temporion@masterzack69";
      eachSystem = nixpkgs.lib.genAttrs (builtins.filter (system: system == "x86_64-linux") (import systems));
      pkgsFor = system: import nixpkgs { inherit system; };
    in
    {
      packages = eachSystem (
        system:
        let
          pkgs = pkgsFor system;

          # Native x86-64 assembly daemon. Rust remains as a reference baseline.
          temporiond = pkgs.stdenv.mkDerivation {
            pname = "temporiond";
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
              mainProgram = "temporiond";
            };
          };

          # The GNOME extension: a thin GJS reader with the daemon's absolute
          # store path baked in, installed to the standard extensions dir.
          temporion = pkgs.stdenvNoCC.mkDerivation {
            pname = "temporion-gnome-extension";
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
                --replace-fail '@TEMPORIOND@' '${temporiond}/bin/temporiond'
              runHook postInstall
            '';
            passthru = {
              extensionUuid = uuid;
              inherit temporiond;
            };
            meta = {
              description = "Temporion GNOME Shell extension (frontend for temporiond)";
              homepage = "https://github.com/MasterZack69/temporion";
              license = pkgs.lib.licenses.agpl3Only;
              platforms = pkgs.lib.platforms.linux;
            };
          };
        in
        {
          inherit temporiond temporion;
          default = temporion;
        }
      );

      # `nix run` runs the daemon standalone (handy for verifying sensors).
      apps = eachSystem (system: {
        default = {
          type = "app";
          program = "${self.packages.${system}.temporiond}/bin/temporiond";
        };
      });

      checks = eachSystem (system: {
        inherit (self.packages.${system}) temporiond temporion;
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
