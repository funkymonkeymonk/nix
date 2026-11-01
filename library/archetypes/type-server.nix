# Shared NixOS type-server archetype.
# Adds the Vector log collector and node_exporter to the headless server base.
{...}: {
  imports = [
    ./headless-server-nixos.nix
    ../../modules/nixos/vector.nix
  ];

  myConfig = {
    vector.enable = true;
    nodeExporter.enable = true;
  };
}
