# microvm-host role module
# Enables MicroVM host infrastructure on any NixOS system (e.g. type-server)
# MicroVM definitions come from /etc/nixos/microvms.nix (generated from cloud-init).
# Per-VM cloud-init files are generated at build time and mounted into each VM.
#
# NOTE: The host configuration must also import microvm.nixosModules.microvm
# (e.g. via the flake or directly in the target).
{
  config,
  lib,
  pkgs,
  options,
  ...
}: let
  cfg = config.myConfig.roles.microvm-host;
  isNixOS = builtins.hasAttr "boot" options;
in {
  imports = [
    ../services/microvm-host
  ];

  # Only apply configuration on NixOS systems
  # Use optionalAttrs for the platform check (not config-dependent)
  # Use mkIf for the enable check (lazy - avoids infinite recursion)
  config = lib.optionalAttrs isNixOS (lib.mkIf cfg.enable {
    services.microvm-host.enable = true;

    boot.kernelModules = lib.mkDefault ["kvm-intel" "kvm-amd"];

    environment.systemPackages = with pkgs; [
      cloud-hypervisor
      virtiofsd
    ];

    # Generate per-VM cloud-init files at build time
    # These are placed at /etc/cloud-init/<hostname>.yaml on the host
    # and mounted into each VM via virtiofs at /etc/cloud-init/
    # Currently contains hostname; expand for secrets (onecli) later.
    environment.etc = lib.mkIf (config.microvm.vms != {}) (
      builtins.listToAttrs (map (name: {
        name = "cloud-init/${name}.yaml";
        value = {
          text = ''
            #cloud-config
            hostname: ${name}
          '';
          mode = "0644";
        };
      }) (builtins.attrNames config.microvm.vms))
    );
  });
}
