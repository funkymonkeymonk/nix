# Prometheus metrics collector for NixOS (type-server).
#
# Wraps the native NixOS `services.prometheus` + `services.prometheus.exporters.node`
# modules with this repo's myConfig.* option convention (matching
# modules/nixos/vector.nix and modules/nixos/loki.nix, and the option names
# used by the Darwin equivalents in
# modules/services/{prometheus,node-exporter}/darwin.nix — those are a
# separate module tree entirely, hand-rolled via launchd since nix-darwin
# has no native Prometheus service; NixOS does, so this module is a thin
# wrapper instead).
#
# Basic alert rules (service down, high memory, low disk) are wired here —
# Prometheus evaluates rules; modules/nixos/alertmanager.nix routes/dedupes
# them (with a documented null-receiver placeholder — see that module).
#
# Federation: set `openFirewallTailscale = true` to allow this host's
# Prometheus to be queried remotely over Tailscale only (e.g. by another
# host's Grafana instance adding this Prometheus as a second datasource).
# See tests/test-nixos-observability.nix for coverage.
{
  config,
  lib,
  options,
  ...
}:
with lib; let
  cfg = config.myConfig.prometheus;
  nodeExporterCfg = config.myConfig.nodeExporter;

  # Not every NixOS target that imports this module also imports
  # modules/nixos/alertmanager.nix — guard alertmanager wiring on option
  # *presence* so this module works standalone (mirrors the same guard
  # added to the Darwin prometheus module in PR #432 for
  # bifrost/oMLX/alertmanager).
  hasAlertmanager = builtins.hasAttr "alertmanager" (options.myConfig or {});

  alertmanagerEnabled = hasAlertmanager && config.myConfig.alertmanager.enable;

  # Basic alert rules for critical service health, matching the pattern
  # established for darwin-server in PR #432
  # (modules/services/prometheus/darwin.nix).
  alertRules = {
    groups = [
      {
        name = "basic-service-health";
        rules = [
          {
            alert = "PrometheusTargetDown";
            expr = "up == 0";
            for = "5m";
            labels.severity = "critical";
            annotations = {
              summary = "{{ $labels.job }} target down";
              description = "Scrape target {{ $labels.instance }} for job {{ $labels.job }} has been down for more than 5 minutes.";
            };
          }
          {
            alert = "HostHighMemoryUsage";
            expr = "node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes < 0.1";
            for = "5m";
            labels.severity = "warning";
            annotations = {
              summary = "Host memory nearly exhausted";
              description = "Available memory on {{ $labels.instance }} has been below 10% for more than 5 minutes.";
            };
          }
          {
            alert = "HostOutOfDiskSpace";
            expr = ''node_filesystem_avail_bytes{fstype!="tmpfs"} / node_filesystem_size_bytes{fstype!="tmpfs"} < 0.1'';
            for = "5m";
            labels.severity = "warning";
            annotations = {
              summary = "Host disk space nearly exhausted";
              description = "Available disk space on {{ $labels.instance }} mount {{ $labels.mountpoint }} has been below 10% for more than 5 minutes.";
            };
          }
        ];
      }
    ];
  };
in {
  options.myConfig.prometheus = {
    enable = mkEnableOption "Prometheus metrics collector";

    port = mkOption {
      type = types.port;
      default = 9090;
      description = "Port for Prometheus HTTP server.";
    };

    retention = mkOption {
      type = types.str;
      default = "15d";
      description = "TSDB retention time (e.g. 15d, 30d).";
    };

    openFirewallTailscale = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Open Prometheus's port on the tailscale0 interface only, so it can
        be queried remotely over Tailscale (e.g. by another host's Grafana
        instance federating this Prometheus as a second datasource). Does
        not open the port on any other interface.
      '';
    };
  };

  options.myConfig.nodeExporter = {
    enable = mkEnableOption "Prometheus node_exporter for system metrics";

    port = mkOption {
      type = types.port;
      default = 9100;
      description = "Port for node_exporter HTTP server.";
    };
  };

  config = mkMerge [
    (mkIf cfg.enable {
      services.prometheus = {
        enable = true;
        port = cfg.port;
        retentionTime = cfg.retention;
        rules = [(builtins.toJSON alertRules)];
        alertmanagers =
          optional alertmanagerEnabled
          {
            static_configs = [{targets = ["localhost:${toString config.myConfig.alertmanager.port}"];}];
          };
        scrapeConfigs =
          [
            {
              job_name = "prometheus";
              static_configs = [{targets = ["localhost:${toString cfg.port}"];}];
            }
          ]
          ++ optional nodeExporterCfg.enable {
            job_name = "node";
            static_configs = [{targets = ["localhost:${toString nodeExporterCfg.port}"];}];
          };
      };

      networking.firewall.interfaces."tailscale0".allowedTCPPorts =
        mkIf cfg.openFirewallTailscale [cfg.port];
    })
    (mkIf nodeExporterCfg.enable {
      services.prometheus.exporters.node = {
        enable = true;
        port = nodeExporterCfg.port;
      };
    })
  ];
}
