# MicroVM host infrastructure service module
# Provides: bridge networking, DNS logging, connection monitoring.
# MicroVM definitions come from /etc/nixos/microvms.nix (generated from cloud-init).
# Enabled via the microvm-host role.
# NOTE: This module uses NixOS-specific options and will only apply config on NixOS systems.
{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.services.microvm-host;
  bridgeIp = builtins.head (builtins.split "/" cfg.bridgeSubnet);
  cloudInitDir = "/var/lib/microvms/cloud-init";
in {
  options.services.microvm-host = {
    enable = mkEnableOption "MicroVM host infrastructure (bridge, DNS logging, connection monitoring)";

    bridgeName = mkOption {
      type = types.str;
      default = "microbr";
      description = "Name of the bridge interface for microvm networking";
    };

    bridgeSubnet = mkOption {
      type = types.str;
      default = "192.168.83.1/24";
      description = "Subnet for the microvm bridge (CIDR notation)";
    };

    externalInterface = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "External interface for NAT masquerade. Null = auto-detect from default route.";
    };

    dnsForwarders = mkOption {
      type = types.listOf types.str;
      default = ["8.8.8.8" "1.1.1.1"];
      description = "Upstream DNS servers for unbound";
    };

    logQueries = mkOption {
      type = types.bool;
      default = true;
      description = "Log all DNS queries from microvms via unbound";
    };

    logConnections = mkOption {
      type = types.bool;
      default = true;
      description = "Log all new connections from microvms via nftables";
    };
  };

  # Only apply configuration when enabled
  # Note: This module should only be imported on NixOS systems where boot.* options exist
  config = lib.mkIf cfg.enable {
    boot.kernelModules = ["kvm-intel" "kvm-amd" "tap" "bridge"];

    # Bridge networking
    systemd.network = {
      netdevs."20-${cfg.bridgeName}" = {
        netdevConfig = {
          Kind = "bridge";
          Name = cfg.bridgeName;
        };
      };

      networks."20-${cfg.bridgeName}" = {
        matchConfig.Name = cfg.bridgeName;
        addresses = [{Address = cfg.bridgeSubnet;}];
      };

      networks."21-microvm-tap" = {
        matchConfig.Name = "microvm-*";
        networkConfig.Bridge = cfg.bridgeName;
      };
    };

    # NAT for microvm egress
    networking.nat = {
      enable = true;
      internalInterfaces = [cfg.bridgeName];
      inherit (cfg) externalInterface;
    };

    # DNS logging via unbound
    services.unbound = mkIf cfg.logQueries {
      enable = true;
      settings.server = {
        interface = [bridgeIp];
        access-control = ["${cfg.bridgeSubnet} allow"];
        verbosity = 1;
        log-queries = "yes";
      };
      settings.forward-zone = [
        {
          name = ".";
          forward-addr = cfg.dnsForwarders;
        }
      ];
    };

    # Connection logging via nftables
    networking.nftables = mkIf cfg.logConnections {
      enable = true;
      tables.microvm-egress = {
        family = "inet";
        content = ''
          chain forward {
            type filter hook forward priority 10; policy accept;
            iifname "${cfg.bridgeName}" ct state new log prefix "microvm-egress: " accept
          }
        '';
      };
    };

    # Host packages
    environment.systemPackages = with pkgs; [
      cloud-hypervisor
      virtiofsd
    ];

    # Cloud-init directory for per-VM files (generated at build time)
    systemd.tmpfiles.rules = [
      "d ${cloudInitDir} 0755 root root -"
    ];
  };
}
