# MicroVM guest module - runs INSIDE the VM
# This is the main entry point that combines base config + VM-specific networking
# All MicroVMs inherit from modules/microvm/base.nix (shared foundation)
# This file adds: bridge networking from myConfig.microvm options
{
  config,
  lib,
  ...
}: {
  imports = [
    ./base.nix
  ];

  # Guest networking — configured from myConfig.microvm options
  # These are set by the host via the microvms.<name> definition
  networking.interfaces.eth0 = {
    useDHCP = false;
    ipv4.addresses = lib.mkIf (config.myConfig.microvm.ipAddress != null) [
      {
        address = config.myConfig.microvm.ipAddress;
        prefixLength = 24;
      }
    ];
  };

  networking.defaultGateway = lib.mkIf (config.myConfig.microvm.gateway != null) {
    address = config.myConfig.microvm.gateway;
    interface = "eth0";
  };
}
