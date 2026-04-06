# MicroVM host infrastructure service module
# Provides: bridge networking, DNS logging, connection monitoring,
#           cloud-init based VM discovery and auto-start.
# Enabled via the microvm-host role.
{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.services.microvm-host;
  cloudInitFile = "/etc/cloud-init.yaml";
  cloudInitDir = "/var/lib/microvms/cloud-init";
  bridgeIp = builtins.head (builtins.split "/" cfg.bridgeSubnet);
in {
  options.services.microvm-host = {
    enable = mkEnableOption "MicroVM host infrastructure (bridge, DNS logging, connection monitoring, cloud-init VM discovery)";

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

    cloudInitFile = mkOption {
      type = types.path;
      default = cloudInitFile;
      description = "Path to cloud-init YAML file containing microvm definitions";
    };
  };

  config = mkIf cfg.enable {
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

    # Cloud-init directory
    systemd.tmpfiles.rules = [
      "d ${cloudInitDir} 0755 root root -"
    ];

    # Discover and start microvms from cloud-init
    # Reads /etc/cloud-init.yaml, extracts microvm definitions,
    # generates per-VM cloud-init files, and starts each VM
    systemd.services.microvm-discover = {
      description = "Discover and start microvms from cloud-init";
      wantedBy = ["multi-user.target"];
      after = ["network.target"];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
                CI_FILE="${cfg.cloudInitFile}"
                CI_DIR="${cloudInitDir}"

                if [[ ! -f "$CI_FILE" ]]; then
                  echo "No cloud-init file found at $CI_FILE"
                  exit 0
                fi

                # Parse microvm definitions from cloud-init
                # Expected format in /etc/cloud-init.yaml:
                #
                # microvms:
                #   - name: matrix
                #     flake: .#microvm.nixosConfigurations.matrix
                #     ipAddress: 192.168.83.15
                #     autoStart: true
                #   - name: openclaw
                #     flake: .#microvm.nixosConfigurations.openclaw
                #     ipAddress: 192.168.83.16
                #     autoStart: true

                # Extract VM names
                vm_names=$(awk '
                  /^microvms:/ { in_vms=1; next }
                  in_vms && /^[^ -]/ { exit }
                  in_vms && /^  - name:/ { gsub(/^  - name:[[:space:]]*/, ""); print }
                ' "$CI_FILE")

                if [[ -z "$vm_names" ]]; then
                  echo "No microvms defined in cloud-init"
                  exit 0
                fi

                mkdir -p "$CI_DIR"

                for vm_name in $vm_names; do
                  echo "Processing microvm: $vm_name"

                  # Extract VM config
                  flake=$(awk -v name="$vm_name" '
                    /^microvms:/ { in_vms=1; next }
                    in_vms && /^  - name:/ { in_vm=1; gsub(/^  - name:[[:space:]]*/, ""); if ($0 == name) found=1; else { in_vm=0; found=0 } }
                    in_vm && found && /^    flake:/ { gsub(/^    flake:[[:space:]]*/, ""); print; exit }
                  ' "$CI_FILE")

                  ip_address=$(awk -v name="$vm_name" '
                    /^microvms:/ { in_vms=1; next }
                    in_vms && /^  - name:/ { in_vm=1; gsub(/^  - name:[[:space:]]*/, ""); if ($0 == name) found=1; else { in_vm=0; found=0 } }
                    in_vm && found && /^    ipAddress:/ { gsub(/^    ipAddress:[[:space:]]*/, ""); print; exit }
                  ' "$CI_FILE")

                  auto_start=$(awk -v name="$vm_name" '
                    /^microvms:/ { in_vms=1; next }
                    in_vms && /^  - name:/ { in_vm=1; gsub(/^  - name:[[:space:]]*/, ""); if ($0 == name) found=1; else { in_vm=0; found=0 } }
                    in_vm && found && /^    autoStart:/ { gsub(/^    autoStart:[[:space:]]*/, ""); print; exit }
                  ' "$CI_FILE")

                  # Generate per-VM cloud-init file (hostname + secrets from 1Password via opnix)
                  cat > "$CI_DIR/$vm_name.yaml" << VMEOF
        #cloud-config
        hostname: $vm_name
        VMEOF

                  chmod 644 "$CI_DIR/$vm_name.yaml"

                  # Generate MAC address (deterministic from name)
                  mac_hash=$(echo -n "$vm_name" | sha256sum | cut -c1-8)
                  mac="02:''${mac_hash:0:2}:''${mac_hash:2:2}:''${mac_hash:4:2}:''${mac_hash:6:2}:01"

                  # Start the microvm if autoStart is true
                  if [[ "$auto_start" == "true" ]]; then
                    echo "Starting microvm: $vm_name (flake: $flake, IP: $ip_address, MAC: $mac)"

                    # Create systemd service for this VM
                    service_file="/etc/systemd/system/microvm-${vm_name}.service"
                    cat > "$service_file" << SVCEOF
        [Unit]
        Description=MicroVM $vm_name
        After=network.target microvm-discover.service
        Requires=microvm-discover.service

        [Service]
        Type=simple
        ExecStart=${pkgs.nix}/bin/nix run $flake.config.microvm.declarationRunner --impure
        Restart=on-failure
        RestartSec=30

        [Install]
        WantedBy=multi-user.target
        SVCEOF
                    systemctl daemon-reload
                    systemctl enable --now "microvm-${vm_name}.service" || true
                  fi
                done
      '';
    };
  };
}
