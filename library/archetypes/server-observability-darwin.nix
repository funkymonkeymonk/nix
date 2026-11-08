# Shared telemetry capabilities for headless Darwin servers.
{...}: {
  imports = [
    ../../modules/services/node-exporter/darwin.nix
    ../../modules/services/vector/darwin.nix
  ];

  myConfig = {
    vector.enable = true;
    collector.destinationHostname = "drlight";
  };
}
