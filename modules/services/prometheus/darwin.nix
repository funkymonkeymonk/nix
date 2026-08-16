# Prometheus metrics collector for Darwin (macOS)
# Scrapes bifrost, vllm-mlx, node-exporter, and itself.
# Stores time-series data locally for ad-hoc querying.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.myConfig.prometheus;

  commonLib = import ../../common/lib.nix {inherit lib;};

  primaryUser = commonLib.primaryUser config;
  darwinHomeDir = commonLib.darwinHomeDir config;
  dataDir = cfg.dataDir;

  # Minimal static scrape config targeting local LLM stack
  prometheusConfig = {
    global.scrape_interval = "15s";
    global.evaluation_interval = "15s";

    scrape_configs = [
      {
        job_name = "prometheus";
        static_configs = [{targets = ["localhost:${toString cfg.port}"];}];
      }
      {
        job_name = "node";
        static_configs = [{targets = ["localhost:${toString config.myConfig.nodeExporter.port}"];}];
      }
      {
        job_name = "bifrost";
        static_configs = [{targets = ["localhost:${toString config.myConfig.bifrost.port}"];}];
        metrics_path = "/metrics";
      }
      {
        job_name = "vllm-mlx";
        static_configs = [{targets = ["localhost:${toString config.myConfig.vllmMlx.server.port}"];}];
        metrics_path = "/metrics";
      }
    ];
  };

  configFile = pkgs.writeText "prometheus.yml" (builtins.toJSON prometheusConfig);

  prometheusScript = pkgs.writeShellScript "prometheus-launchd-service" ''
    set -euo pipefail

    mkdir -p "${dataDir}"

    exec ${pkgs.prometheus}/bin/prometheus \
      --config.file ${configFile} \
      --storage.tsdb.path "${dataDir}" \
      --storage.tsdb.retention.time ${cfg.retention} \
      --web.listen-address=${lib.escapeShellArg cfg.listenAddress} \
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

    listenAddress = lib.mkOption {
      type = lib.types.str;
      default = "0.0.0.0:9090";
      description = "Bind address for Prometheus HTTP server";
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
