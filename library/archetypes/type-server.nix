# Shared NixOS type-server archetype.
# Adds the Vector log collector to the headless server base; node_exporter is catalog-driven.
{...}: {
  imports = [
    ./headless-server-nixos.nix
    ../../modules/nixos/vector.nix
  ];

  myConfig = {
    collector.destinationHostname = "drlight";
    vector.enable = true;
  };
}
