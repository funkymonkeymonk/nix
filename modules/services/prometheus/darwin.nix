# Prometheus metrics collector for Darwin (macOS)
# Scrapes bifrost, vllm-mlx, node-exporter, and itself.
# Stores time-series data locally for ad-hoc querying.
{
  config,
  lib,
  pkgs,
  options,
  ...
}: let
  cfg = config.myConfig.prometheus;

  commonLib = import ../../common/lib.nix {inherit lib;};

  primaryUser = commonLib.primaryUser config;
  darwinHomeDir = commonLib.darwinHomeDir config;
  dataDir = cfg.dataDir;

  # Not every darwin target imports every LLM-stack service module (e.g.
  # darwin-server has no bifrost/vllm-mlx). Guard optional scrape targets on
  # whether the option is even declared, so this module works standalone.
  myConfigOptions = options.myConfig or {};
  hasBifrost = builtins.hasAttr "bifrost" myConfigOptions;
  hasVllmMlx = builtins.hasAttr "vllmMlx" myConfigOptions;
  hasAlertmanager = builtins.hasAttr "alertmanager" myConfigOptions;

  # Minimal static scrape config targeting local LLM stack
  prometheusConfig = {
    global.scrape_interval = "15s";
    global.evaluation_interval = "15s";

    rule_files = [rulesFile];

    alerting.alertmanagers = lib.optional hasAlertmanager {
      static_configs = [{targets = ["${config.myConfig.alertmanager.bindAddress}:${toString config.myConfig.alertmanager.port}"];}];
    };

    scrape_configs =
      [
        {
          job_name = "prometheus";
          static_configs = [{targets = ["localhost:${toString cfg.port}"];}];
        }
        {
          job_name = "node";
          static_configs = [{targets = ["localhost:${toString config.myConfig.nodeExporter.port}"];}];
        }
      ]
      ++ lib.optional hasBifrost {
        job_name = "bifrost";
        static_configs = [{targets = ["localhost:${toString config.myConfig.bifrost.port}"];}];
        metrics_path = "/metrics";
      }
      ++ lib.optional hasVllmMlx {
        job_name = "vllm-mlx";
        static_configs = [{targets = ["localhost:${toString config.myConfig.vllmMlx.server.port}"];}];
        metrics_path = "/metrics";
      };
  };

  # Basic alert rules for critical service health. Alertmanager's actual
  # notification receiver is a documented TBD placeholder (see
  # modules/services/alertmanager/darwin.nix) — these rules fire and route
  # to Alertmanager regardless, but produce no external notification until
  # a real receiver is wired up.
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

  rulesFile = pkgs.writeText "prometheus-alert-rules.yml" (builtins.toJSON alertRules);

  configFile = pkgs.writeText "prometheus.yml" (builtins.toJSON prometheusConfig);

  prometheusScript = pkgs.writeShellScript "prometheus-launchd-service" ''
    set -euo pipefail

    mkdir -p "${dataDir}"

    exec ${pkgs.prometheus}/bin/prometheus \
      --config.file ${configFile} \
      --storage.tsdb.path "${dataDir}" \
      --storage.tsdb.retention.time ${cfg.retention} \
      --web.listen-address=${cfg.bindAddress}:${toString cfg.port} \
      --web.console.templates=${pkgs.prometheus}/etc/prometheus/consoles \
      --web.console.libraries=${pkgs.prometheus}/etc/prometheus/console_libraries
  '';
in {
  options.myConfig.prometheus = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable Prometheus metrics collector for local LLM stack observability";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 9090;
      description = "Port for Prometheus HTTP server";
    };

    bindAddress = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = "Bind address for Prometheus HTTP server. Defaults to loopback-only since Grafana queries it on the same host; set to protoman's LAN IP for cross-host 192.168.83.0/24 access.";
    };

    dataDir = lib.mkOption {
      type = lib.types.str;
      default = "${darwinHomeDir}/Library/Application Support/Prometheus";
      description = "Directory for Prometheus TSDB storage";
    };

    retention = lib.mkOption {
      type = lib.types.str;
      default = "7d";
      description = "TSDB retention time (e.g. 7d, 24h, 30d)";
    };
  };

  config = lib.mkIf cfg.enable {
    launchd.daemons.prometheus = {
      command = prometheusScript;
      serviceConfig = {
        Label = "org.prometheus.server";
        RunAtLoad = true;
        KeepAlive = true;
        UserName = primaryUser;
        StandardOutPath = "/tmp/prometheus.log";
        StandardErrorPath = "/tmp/prometheus.error.log";
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

    myConfig.serviceRegistry = commonLib.mkServiceRegistry "prometheus" {
      displayName = "Prometheus";
      port = cfg.port;
      label = "org.prometheus.server";
      errorLog = "/tmp/prometheus.error.log";
      enabled = cfg.enable;
    };
  };
}
