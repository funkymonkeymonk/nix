{
  inputs,
  catalog ? import ./catalog.nix {inherit inputs;},
  ...
}: let
  lib = inputs.nixpkgs.lib;
  observabilityInventory = import ./observability-inventory.nix {inherit catalog;};
  projectMachineModules = import ./modules.nix {inherit inputs catalog;};
  nixpkgsConfig = import ../lib/nixpkgs-config.nix;
  withSpecialArgs = import ./with-special-args.nix {inherit lib;};
  nixosBaseModules = machine: [
    ({...}: {
      networking.hostName = machine.hostname;
      nixpkgs.hostPlatform = machine.system;
    })
    (nixpkgsConfig {inherit inputs;})
    (import ../../modules)
    inputs.opnix.nixosModules.default
    ./remote-builders.nix
    inputs.home-manager.nixosModules.home-manager
    {
      home-manager.sharedModules = [
        inputs.opnix.homeManagerModules.default
      ];
    }
  ];
  nixosModuleArgs = machine:
    (
      if machine.builder == "mk-system"
      then inputs // {inherit inputs;}
      else {}
    )
    // machine.extraSpecialArgs;
  darwinModuleArgs = machine: {inherit inputs;} // machine.extraSpecialArgs;
  nixosModule = machine: let
    moduleArgs = nixosModuleArgs machine;
    machineModules = projectMachineModules {inherit machine;};
  in
    if machine.builder == "mk-system"
    then let
      baseModules = nixosBaseModules machine;
    in {
      imports = map (withSpecialArgs moduleArgs) (baseModules ++ machineModules);
      config =
        {
          _module.args = moduleArgs;
        }
        // lib.optionalAttrs (machine.overrides != {}) {
          myConfig = lib.mkMerge [
            (lib.mkOverride 50 machine.overrides)
          ];
        };
    }
    else {
      imports = map (withSpecialArgs moduleArgs) machineModules;
      config._module.args = moduleArgs;
    };
  darwinModule = machine: let
    moduleArgs = darwinModuleArgs machine;
    # Darwin archetypes own the shared project modules; the system-wide Opnix
    # and remote-builder modules are injected here for every catalog machine.
    baseModules = [
      ({...}: {
        networking.hostName = machine.hostname;
        nixpkgs.hostPlatform = machine.system;
      })
      (nixpkgsConfig {inherit inputs;})
      inputs.opnix.darwinModules.default
      ./remote-builders.nix
      (observabilityInventory.machineModule machine)
    ];
  in {
    imports = map (withSpecialArgs moduleArgs) (baseModules ++ machine.modules);
    config =
      {
        _module.args = moduleArgs;
      }
      // lib.optionalAttrs (machine.overrides != {}) {
        myConfig = lib.mkMerge [
          machine.overrides
          (lib.mkForce {})
        ];
      };
  };
  asMachine = _: machine:
    {system = machine.system;}
    // lib.optionalAttrs (machine ? install) {
      inherit (machine) install;
    }
    // (
      if machine.kind == "nixos"
      then {nixos = nixosModule machine;}
      else {"nix-darwin" = darwinModule machine;}
    );
in {
  machines = lib.mapAttrs asMachine catalog;
}
