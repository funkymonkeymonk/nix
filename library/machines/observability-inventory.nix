{catalog}: let
  machineNames = builtins.attrNames catalog;
  exporterMetadata = machine: machine.nodeExporter or {};
  enabled = machine: (exporterMetadata machine).enable or false;
  exporterPort = machine: (exporterMetadata machine).port or 9100;
  exporterAddress = machine: (exporterMetadata machine).address or machine.hostname;
  targets = builtins.concatLists (map (name: let
    machine = catalog.${name};
    address = exporterAddress machine;
    port = exporterPort machine;
    targetAddress =
      if builtins.match ".*:.*" address != null
      then "[${address}]"
      else address;
  in
    if enabled machine
    then [
      {
        inherit name address port;
        inherit (machine) kind;
        target = "${targetAddress}:${toString port}";
      }
    ]
    else [])
  machineNames);
in {
  inherit targets;

  machineModule = machine: {
    lib,
    options,
    ...
  }: let
    metadata = exporterMetadata machine;
    hasNodeExporter = builtins.hasAttr "myConfig" options && builtins.hasAttr "nodeExporter" options.myConfig;
    hasNodeExporterPort = hasNodeExporter && builtins.hasAttr "port" options.myConfig.nodeExporter;
  in {
    config =
      {
        _module.args.nodeExporterInventory = targets;
      }
      // lib.optionalAttrs hasNodeExporter {
        myConfig.nodeExporter =
          {
            enable = lib.mkForce (metadata.enable or false);
          }
          // lib.optionalAttrs hasNodeExporterPort {
            port = lib.mkForce (metadata.port or 9100);
          };
      };
  };
}
