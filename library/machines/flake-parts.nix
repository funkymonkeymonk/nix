{
  inputs,
  libraryLib,
  ...
}: let
  catalog = import ./catalog.nix {inherit inputs;};
  observabilityInventory = import ./observability-inventory.nix {inherit catalog;};
  projectMachineModules = import ./modules.nix {inherit inputs;};
  lib = inputs.nixpkgs.lib;
  nixosMachines = lib.filterAttrs (_: machine: machine.kind == "nixos") catalog;
  darwinMachines = lib.filterAttrs (_: machine: machine.kind == "darwin") catalog;
  mkNixos = _: machine:
    if machine.builder == "mk-system"
    then
      libraryLib.mkNixosSystem {
        inherit inputs;
        inherit (machine) hostname system overrides extraSpecialArgs;
        modules = projectMachineModules {
          inherit machine;
          includeDisko = true;
        };
      }
    else
      inputs.nixpkgs.lib.nixosSystem {
        inherit (machine) system;
        modules = projectMachineModules {
          inherit machine;
          includeDisko = true;
        };
        specialArgs = machine.extraSpecialArgs;
      };
  mkDarwin = _: machine:
    libraryLib.mkDarwinSystem {
      inherit inputs;
      inherit (machine) hostname system overrides extraSpecialArgs;
      modules = [(observabilityInventory.machineModule machine)] ++ machine.modules;
    };
in {
  flake.nixosConfigurations = lib.mapAttrs mkNixos nixosMachines;
  flake.darwinConfigurations = lib.mapAttrs mkDarwin darwinMachines;
}
