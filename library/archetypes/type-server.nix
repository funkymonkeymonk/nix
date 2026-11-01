# Shared NixOS type-server archetype.
# Adds the Vector log collector to the headless server base; node_exporter is catalog-driven.
{lib, ...}: {
  imports = [
    ./headless-server-nixos.nix
    ../../modules/nixos/vector.nix
  ];

  myConfig = {
    collector.destinationHostname = lib.mkDefault "drlight";
    vector.enable = true;
  };
}
