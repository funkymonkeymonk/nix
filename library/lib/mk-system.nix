{lib}: let
  mkNixpkgsConfigModule = import ./nixpkgs-config.nix;
in rec {
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
          }
          (mkNixpkgsConfigModule {inherit inputs;})
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
            nixpkgs.hostPlatform = system;
          }
          (mkNixpkgsConfigModule {inherit inputs;})
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
