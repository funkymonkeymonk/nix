{
  inputs,
  catalog ? import ./catalog.nix {inherit inputs;},
}: {
  machine,
  includeDisko ? false,
}: let
  observabilityInventory = import ./observability-inventory.nix {inherit catalog;};
  diskoModules =
    if includeDisko && (machine.disko or false)
    then [inputs.disko.nixosModules.disko]
    else [];
in
  diskoModules
  ++ [
    ../../modules/nixos/ssh-host-key-fingerprint.nix
    (observabilityInventory.machineModule machine)
  ]
  ++ machine.modules
