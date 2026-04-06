# microvm-host role module
# Enables MicroVM host infrastructure on any NixOS system (e.g. type-server)
# When enabled, the system reads /etc/cloud-init.yaml for microvm definitions
# and automatically starts them with bridge networking, DNS logging, and connection monitoring.
#
# NOTE: The host configuration must also import microvm.nixosModules.microvm
# (e.g. via the flake or directly in the target).
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.myConfig.roles.microvm-host;
in {
  # Import the microvm host service module
  imports = [
    ../services/microvm-host
  ];

  config = lib.mkIf cfg.enable {
    # Enable the microvm host service
    services.microvm-host.enable = true;

    # Ensure KVM modules are loaded
    boot.kernelModules = lib.mkDefault ["kvm-intel" "kvm-amd"];

    # Packages for microvm management
    environment.systemPackages = with pkgs; [
      cloud-hypervisor
      virtiofsd
    ];
  };
}
