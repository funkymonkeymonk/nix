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

    exec ${pkgs.prometheus-node-exporter}/bin/node_exporter \
      --web.listen-address=${lib.escapeShellArg cfg.listenAddress} \
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
      default = "0.0.0.0:9100";
      description = "Bind address for node_exporter HTTP server";
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
