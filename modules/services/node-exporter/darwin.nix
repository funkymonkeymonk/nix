# Prometheus node_exporter for Darwin (macOS)
# Exposes system metrics: CPU, memory, disk, network, load.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.myConfig.nodeExporter;

  commonLib = import ../../common/lib.nix {inherit lib;};

  primaryUser = commonLib.primaryUser config;
  darwinHomeDir = commonLib.darwinHomeDir config;

  nodeExporterScript = pkgs.writeShellScript "node-exporter-launchd-service" ''
    set -euo pipefail

    if ${lib.boolToString cfg.listenOnTailscale}; then
      echo "Waiting for Tailscale before binding node_exporter"
      until TAILSCALE_IP=$(${pkgs.tailscale}/bin/tailscale ip -4 2>/dev/null) && [ -n "$TAILSCALE_IP" ]; do
        /bin/sleep 5
      done
      LISTEN_ADDRESS="$TAILSCALE_IP:${toString cfg.port}"
    else
      LISTEN_ADDRESS=${lib.escapeShellArg cfg.listenAddress}
    fi

    exec ${pkgs.prometheus-node-exporter}/bin/node_exporter \
      --web.listen-address="$LISTEN_ADDRESS" \
      --path.rootfs=/ \
      --collector.disable-defaults \
      --collector.cpu \
      --collector.loadavg \
      --collector.meminfo \
      --collector.diskstats \
      --collector.filesystem \
      --collector.netdev \
      --collector.os \
      --collector.time \
      --collector.uname
  '';
in {
  options.myConfig.nodeExporter = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable Prometheus node_exporter for system metrics";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 9100;
      description = "Port for node_exporter HTTP server";
    };

    listenAddress = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1:${toString cfg.port}";
      description = ''
        Bind address for node_exporter when listenOnTailscale is false. The default
        is loopback-only because nix-darwin does not provide interface-specific
        inbound firewall rules.
      '';
    };

    listenOnTailscale = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Resolve the current Tailscale IPv4 address at service startup and bind only
        to that address. The service waits for Tailscale to become available, which
        keeps the metrics endpoint off the machine's LAN interfaces.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    launchd.daemons.node-exporter = {
      command = nodeExporterScript;
      serviceConfig = {
        Label = "org.prometheus.node-exporter";
        RunAtLoad = true;
        KeepAlive = true;
        UserName = primaryUser;
        StandardOutPath = "/tmp/node-exporter.log";
        StandardErrorPath = "/tmp/node-exporter.error.log";
        WorkingDirectory = darwinHomeDir;
        EnvironmentVariables = {
          HOME = darwinHomeDir;
          USER = primaryUser;
        };
      };
    };

    myConfig.serviceRegistry = commonLib.mkServiceRegistry "node-exporter" {
      displayName = "Node Exporter";
      port = cfg.port;
      label = "org.prometheus.node-exporter";
      errorLog = "/tmp/node-exporter.error.log";
      enabled = cfg.enable;
    };
  };
}
