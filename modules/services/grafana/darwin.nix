# Grafana dashboard/visualization server for Darwin (macOS)
# Provisions Prometheus + Loki as datasources and a basic system-overview
# dashboard. Reachable via Tailscale (binds 0.0.0.0; protoman is a headless
# server whose only network path in from outside the LAN is the tailnet —
# see PR description for the full rationale).
#
# OPEN ITEM: Grafana admin credentials are left at Grafana's built-in
# default (admin/admin, forced change on first login) since no secret
# management has been wired up for this service yet. Wiring a real admin
# password via 1Password/opnix is a suggested follow-up.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.myConfig.grafana;

  commonLib = import ../../common/lib.nix {inherit lib;};

  primaryUser = commonLib.primaryUser config;
  darwinHomeDir = commonLib.darwinHomeDir config;
  dataDir = cfg.dataDir;

  prometheusUrl = "http://${config.myConfig.prometheus.bindAddress}:${toString config.myConfig.prometheus.port}";
  lokiUrl = "http://${config.myConfig.loki.bindAddress}:${toString config.myConfig.loki.port}";

  datasourcesYml = pkgs.writeText "datasources.yml" (builtins.toJSON {
    apiVersion = 1;
    datasources = [
      {
        name = "Prometheus";
        type = "prometheus";
        access = "proxy";
        url = prometheusUrl;
        isDefault = true;
      }
      {
        name = "Loki";
        type = "loki";
        access = "proxy";
        url = lokiUrl;
      }
    ];
  });

  systemOverviewDashboard = pkgs.writeText "system-overview.json" (builtins.toJSON {
    title = "protoman: System Overview";
    uid = "protoman-system-overview";
    schemaVersion = 39;
    panels = [
      {
        id = 1;
        title = "CPU Usage";
        type = "timeseries";
        gridPos = {
          h = 8;
          w = 12;
          x = 0;
          y = 0;
        };
        targets = [
          {
            datasource.type = "prometheus";
            expr = "100 - (avg(rate(node_cpu_seconds_total{mode=\"idle\"}[5m])) * 100)";
          }
        ];
      }
      {
        id = 2;
        title = "Memory Available";
        type = "timeseries";
        gridPos = {
          h = 8;
          w = 12;
          x = 12;
          y = 0;
        };
        targets = [
          {
            datasource.type = "prometheus";
            expr = "node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes * 100";
          }
        ];
      }
      {
        id = 3;
        title = "Disk Free";
        type = "timeseries";
        gridPos = {
          h = 8;
          w = 12;
          x = 0;
          y = 8;
        };
        targets = [
          {
            datasource.type = "prometheus";
            expr = "node_filesystem_avail_bytes{fstype!=\"tmpfs\"} / node_filesystem_size_bytes{fstype!=\"tmpfs\"} * 100";
          }
        ];
      }
      {
        id = 4;
        title = "Service Logs";
        type = "logs";
        gridPos = {
          h = 8;
          w = 12;
          x = 12;
          y = 8;
        };
        targets = [
          {
            datasource.type = "loki";
            expr = "{job=\"vector\"}";
          }
        ];
      }
    ];
  });

  dashboardsDir = pkgs.runCommand "grafana-dashboards" {} ''
    mkdir -p $out
    cp ${systemOverviewDashboard} $out/system-overview.json
  '';

  dashboardsProviderYml = pkgs.writeText "dashboards.yml" (builtins.toJSON {
    apiVersion = 1;
    providers = [
      {
        name = "protoman";
        type = "file";
        options.path = "${dashboardsDir}";
      }
    ];
  });

  # Assemble the provisioning directory tree Grafana expects:
  #   <out>/datasources/*.yml
  #   <out>/dashboards/*.yml (provider config, points at dashboardsDir)
  provisioningDir = pkgs.runCommand "grafana-provisioning" {} ''
    mkdir -p $out/datasources $out/dashboards
    cp ${datasourcesYml} $out/datasources/datasources.yml
    cp ${dashboardsProviderYml} $out/dashboards/dashboards.yml
  '';

  grafanaIni = pkgs.writeText "grafana.ini" ''
    [server]
    http_addr = ${cfg.bindAddress}
    http_port = ${toString cfg.port}
    domain = ${cfg.domain}

    [paths]
    data = ${dataDir}
    logs = ${dataDir}/log
    plugins = ${dataDir}/plugins
    provisioning = ${provisioningDir}
  '';

  grafanaScript = pkgs.writeShellScript "grafana-launchd-service" ''
    set -euo pipefail

    mkdir -p "${dataDir}/log" "${dataDir}/plugins"

    exec ${pkgs.grafana}/bin/grafana server \
      --config ${grafanaIni} \
      --homepath ${pkgs.grafana}/share/grafana \
      --pidfile "${dataDir}/grafana.pid"
  '';
in {
  options.myConfig.grafana = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable Grafana dashboard/visualization server with Prometheus + Loki datasources";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 3000;
      description = "Port for Grafana HTTP server";
    };

    bindAddress = lib.mkOption {
      type = lib.types.str;
      default = "0.0.0.0";
      description = "Bind address for Grafana HTTP server. Defaults to all interfaces — protoman is a headless server reachable only via Tailscale, which is treated as the network access boundary here rather than a specific bind IP.";
    };

    domain = lib.mkOption {
      type = lib.types.str;
      default = "localhost";
      description = "Domain name used for building absolute URLs (e.g. in alert links). Set to protoman's Tailscale hostname/MagicDNS name once known.";
    };

    dataDir = lib.mkOption {
      type = lib.types.str;
      default = "${darwinHomeDir}/Library/Application Support/Grafana";
      description = "Directory for Grafana's sqlite database, logs, and plugins";
    };
  };

  config = lib.mkIf cfg.enable {
    launchd.daemons.grafana = {
      command = grafanaScript;
      serviceConfig = {
        Label = "com.grafana.server";
        RunAtLoad = true;
        KeepAlive = true;
        UserName = primaryUser;
        StandardOutPath = "/tmp/grafana.log";
        StandardErrorPath = "/tmp/grafana.error.log";
        WorkingDirectory = darwinHomeDir;
        EnvironmentVariables = {
          HOME = darwinHomeDir;
          USER = primaryUser;
        };
      };
    };

    system.activationScripts.postActivation.text = lib.mkAfter ''
      mkdir -p "${dataDir}"
    '';

    myConfig.serviceRegistry = commonLib.mkServiceRegistry "grafana" {
      displayName = "Grafana";
      port = cfg.port;
      label = "com.grafana.server";
      errorLog = "/tmp/grafana.error.log";
      enabled = cfg.enable;
    };
  };
}
