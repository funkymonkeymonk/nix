{lib}: rec {
  mkDarwinSystem = {
    inputs,
    hostname,
    system ? "aarch64-darwin",
    modules ? [],
    overrides ? {},
    extraSpecialArgs ? {},
  }: let
    inherit (inputs) nix-darwin;
  in
    nix-darwin.lib.darwinSystem {
      inherit system;
      specialArgs = {inherit inputs;} // extraSpecialArgs;
      modules =
        [
          {
            networking.hostName = hostname;
            system.configurationRevision = inputs.self.rev or inputs.self.dirtyRev or null;
            nixpkgs = {
              config = {
                allowUnfree = true;
                permittedInsecurePackages = [
                  "electron-39.8.10"
                  "google-chrome-144.0.7559.97"
                  "olm-3.2.16"
                ];
                allowInsecurePredicate = attrs: let
                  pname = attrs.pname or attrs.name or "";
                  fullName = "${pname}-${attrs.version or ""}";
                in
                  pname
                  == "openclaw"
                  || builtins.elem fullName ["electron-39.8.10" "google-chrome-144.0.7559.97" "olm-3.2.16"];
              };
              overlays = [
                (final: _prev: {
                  stable = import inputs.nixpkgs-stable {
                    inherit (final) system config;
                  };
                })
                (final: _prev: {
                  inherit (inputs.devenv.packages.${final.stdenv.hostPlatform.system}) devenv;
                })
                (final: _prev: {
                  zellij-pane-tracker = inputs.zellij-pane-tracker.packages.${final.stdenv.hostPlatform.system}.default;
                })
                (import ../../overlays)
              ];
            };
          }
          (import ../../modules)
        ]
        ++ modules
        ++ lib.optional (overrides != {}) {
          myConfig = lib.mkMerge [
            overrides
            (lib.mkForce {})
          ];
        };
    };

  mkNixosSystem = {
    inputs,
    hostname,
    system ? "x86_64-linux",
    modules ? [],
    overrides ? {},
    extraSpecialArgs ? {},
  }: let
    inherit (inputs) nixpkgs;
  in
    nixpkgs.lib.nixosSystem {
      inherit system;
      specialArgs = inputs // {inherit inputs;} // extraSpecialArgs;
      modules =
        [
          {
            networking.hostName = hostname;
            system.configurationRevision = inputs.self.rev or inputs.self.dirtyRev or null;
            nixpkgs = {
              config = {
                allowUnfree = true;
                permittedInsecurePackages = [
                  "electron-39.8.10"
                  "google-chrome-144.0.7559.97"
                  "olm-3.2.16"
                ];
                allowInsecurePredicate = attrs: let
                  pname = attrs.pname or attrs.name or "";
                  fullName = "${pname}-${attrs.version or ""}";
                in
                  pname
                  == "openclaw"
                  || builtins.elem fullName ["electron-39.8.10" "google-chrome-144.0.7559.97" "olm-3.2.16"];
              };
              hostPlatform = system;
              overlays = [
                (final: _prev: {
                  stable = import inputs.nixpkgs-stable {
                    inherit (final) system config;
                  };
                })
                (final: _prev: {
                  inherit (inputs.devenv.packages.${final.stdenv.hostPlatform.system}) devenv;
                })
                (final: _prev: {
                  zellij-pane-tracker = inputs.zellij-pane-tracker.packages.${final.stdenv.hostPlatform.system}.default;
                })
                (import ../../overlays)
              ];
            };
          }
          (import ../../modules)
          inputs.home-manager.nixosModules.home-manager
          {
            home-manager.sharedModules = [
              inputs.opnix.homeManagerModules.default
            ];
          }
        ]
        ++ modules
        ++ lib.optional (overrides != {}) {
          myConfig = lib.mkMerge [
            (lib.mkOverride 50 overrides)
          ];
        };
    };
}
