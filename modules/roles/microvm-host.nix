# microvm-host role module
# Enables MicroVM host infrastructure and manages MicroVM lifecycle
#
# Usage:
#   myConfig.roles.microvm-host.enable = true;
#   myConfig.microvms.openclaw = {
#     ip = "192.168.83.16";
#     memory = 2048;
#   };
#
# Features:
#   - Each VM inherits from base MicroVM config
#   - MAC addresses auto-generated from name (deterministic)
#   - Cloud-init files auto-generated
#   - Support for direct microvm.vms for complex cases
#   - Validation (duplicate IPs, subnet checking)
#
# NOTE: The host configuration must also import microvm.nixosModules.microvm
# (e.g. via the flake or directly in the target).
{
  config,
  lib,
  pkgs,
  options,
  ...
}:
with lib; let
  cfg = config.myConfig.roles.microvm-host;
  isNixOS = builtins.hasAttr "boot" options;

  # Helper: Generate MAC address from VM name (deterministic)
  mkMac = name: let
    hash = builtins.substring 0 10 (builtins.hashString "sha256" name);
    # Convert hash to MAC format (02:XX:XX:XX:XX:XX)
    pairs =
      lib.genList (
        i: let
          idx = i * 2;
        in
          builtins.substring idx 2 hash
      )
      5;
  in "02:${lib.concatStringsSep ":" pairs}";

  # Helper: Check if IP is in valid bridge subnet
  isValidBridgeIp = ip: lib.hasPrefix "192.168.83." ip;

  # Transform myConfig.microvms into microvm.vms entries
  userVms = lib.mapAttrs (
    name: vmCfg:
      {
        # Use provided flake or default
        flake = vmCfg.flake or ".#microvm.nixosConfigurations.${name}";

        # Standard interfaces (tap + any extras)
        interfaces =
          [
            {
              type = "tap";
              id = "microvm-${name}";
              mac = vmCfg.mac or (mkMac name);
            }
          ]
          ++ (vmCfg.extraInterfaces or []);

        # Standard hypervisor
        hypervisor = pkgs.cloud-hypervisor;

        # Writable overlay store
        writableStoreOverlay = "/nix/.rw-store";

        # Standard shares + any extras
        shares =
          [
            {
              tag = "ro-store";
              source = "/nix/store";
              mountPoint = "/nix/.ro-store";
              proto = "virtiofs";
            }
            {
              tag = "cloud-init";
              source = "/var/lib/microvms/cloud-init";
              mountPoint = "/etc/cloud-init";
              proto = "virtiofs";
            }
          ]
          ++ (vmCfg.extraShares or []);

        # Autostart, Memory and vCPU (microvm.nix passes these to cloud-hypervisor)
        inherit (vmCfg) autostart memory vcpus;
      }
      // (vmCfg.customConfig or {})
  ) (lib.filterAttrs (_n: v: v.enable) config.myConfig.microvms);

  # Check for duplicate IPs
  allIps = lib.mapAttrsToList (_: v: v.ip) (lib.filterAttrs (_: v: v.enable) config.myConfig.microvms);
  duplicateIps = lib.filter (ip: lib.count (x: x == ip) allIps > 1) allIps;
in {
  imports = [
    ../services/microvm-host
  ];

  config = lib.optionalAttrs isNixOS (
    lib.mkIf cfg.enable (
      # Guard: only apply microvm config if microvm module is available
      lib.optionalAttrs (builtins.hasAttr "microvm" options) {
        # Assertions for validation
        assertions = [
          {
            assertion = duplicateIps == [];
            message = "Duplicate MicroVM IPs detected: ${lib.concatStringsSep ", " duplicateIps}";
          }
        ];

        # Warnings for common mistakes
        warnings = lib.concatLists (lib.mapAttrsToList (
            name: vmCfg:
              lib.optional (!isValidBridgeIp vmCfg.ip) "MicroVM '${name}' IP ${vmCfg.ip} is not in 192.168.83.0/24 bridge subnet"
          )
          config.myConfig.microvms);

        services.microvm-host.enable = true;

        boot.kernelModules = lib.mkDefault ["kvm-intel" "kvm-amd"];

        environment.systemPackages = with pkgs; [
          cloud-hypervisor
          virtiofsd
        ];

        # Transform high-level myConfig.microvms into low-level microvm.vms
        # Also allow direct microvm.vms for complex cases
        # Only set if microvm module is available and there are VMs defined
        microvm.vms = lib.mkIf ((config.myConfig.microvms != {}) || ((config.microvm.vms or {}) != {})) (
          userVms // (config.microvm.vms or {})
        );

        # Generate per-VM cloud-init files at build time
        # These are placed at /etc/cloud-init/<hostname>.yaml on the host
        # and mounted into each VM via virtiofs at /etc/cloud-init/
        environment.etc = lib.mkIf ((config.myConfig.microvms != {}) || ((config.microvm.vms or {}) != {})) (
          let
            allVms = (lib.attrNames config.myConfig.microvms) ++ (lib.attrNames (config.microvm.vms or {}));
          in
            builtins.listToAttrs (map (
                name: {
                  name = "cloud-init/${name}.yaml";
                  value = {
                    text = ''
                      #cloud-config
                      hostname: ${name}
                    '';
                    mode = "0644";
                  };
                }
              )
              allVms)
        );
      }
    )
  );
}
