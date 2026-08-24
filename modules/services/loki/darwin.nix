# Grafana Loki log aggregation for Darwin (macOS)
# Single-binary mode with filesystem storage (TSDB index), matching this
# repo's native-launchd pattern (no containers).
#
# IMPORTANT: this uses pkgs.grafana-loki, NOT pkgs.loki — the latter is an
# unrelated C++ library that happens to share the name in nixpkgs.
#
# Network exposure: bindAddress defaults to 127.0.0.1 (loopback-only). This
# is intentionally *more* restrictive than the requested 192.168.83.0/24
# internal-only requirement — Grafana and Vector both run on the same host
# and only need localhost access. Set bindAddress explicitly (e.g. to
# protoman's actual LAN IP) if cross-host access within 192.168.83.0/24 is
# needed later. See PR description for the full rationale — the agent does
# not have access to protoman's live network configuration to pick a real
# LAN IP as a default.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.myConfig.loki;

  commonLib = import ../../common/lib.nix {inherit lib;};

  primaryUser = commonLib.primaryUser config;
  darwinHomeDir = commonLib.darwinHomeDir config;
  dataDir = cfg.dataDir;

  lokiConfig = {
    auth_enabled = false;

    server = {
      http_listen_address = cfg.bindAddress;
      http_listen_port = cfg.port;
      grpc_listen_address = "127.0.0.1";
      grpc_listen_port = 9096;
    };

    common = {
      path_prefix = dataDir;
      storage.filesystem = {
        chunks_directory = "${dataDir}/chunks";
        rules_directory = "${dataDir}/rules";
      };
      replication_factor = 1;
      ring = {
        instance_addr = "127.0.0.1";
        kvstore.store = "inmemory";
      };
    };

    schema_config.configs = [
      {
        from = "2024-01-01";
        store = "tsdb";
        object_store = "filesystem";
        schema = "v13";
        index = {
          prefix = "index_";
          period = "24h";
        };
      }
    ];

    storage_config = {
      tsdb_shipper = {
        active_index_directory = "${dataDir}/tsdb-index";
        cache_location = "${dataDir}/tsdb-cache";
      };
      filesystem.directory = "${dataDir}/chunks";
    };

    limits_config = {
      retention_period = cfg.retention;
      reject_old_samples = true;
      reject_old_samples_max_age = "168h";
    };

    compactor = {
      working_directory = "${dataDir}/compactor";
      retention_enabled = true;
      delete_request_store = "filesystem";
    };
  };

  configFile = pkgs.writeText "loki-config.yaml" (builtins.toJSON lokiConfig);

  lokiScript = pkgs.writeShellScript "loki-launchd-service" ''
    set -euo pipefail

    mkdir -p "${dataDir}/chunks" "${dataDir}/rules" "${dataDir}/tsdb-index" "${dataDir}/tsdb-cache" "${dataDir}/compactor"

    exec ${pkgs.grafana-loki}/bin/loki \
      -config.file ${configFile}
  '';
in {
  options.myConfig.loki = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable Grafana Loki log aggregation server";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 3100;
      description = "Port for Loki HTTP server (log push + query API)";
    };

    bindAddress = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = "Bind address for Loki HTTP server. Defaults to loopback-only since Grafana/Vector run on the same host; set to protoman's LAN IP for cross-host 192.168.83.0/24 access.";
    };

    dataDir = lib.mkOption {
      type = lib.types.str;
      default = "${darwinHomeDir}/Library/Application Support/Loki";
      description = "Directory for Loki chunks, index, and compactor working data";
    };

    retention = lib.mkOption {
      type = lib.types.str;
      default = "168h";
      description = "Log retention period (e.g. 168h = 7 days, 720h = 30 days)";
    };
  };

  config = lib.mkIf cfg.enable {
    launchd.daemons.loki = {
      command = lokiScript;
      serviceConfig = {
        Label = "org.grafana.loki";
        RunAtLoad = true;
        KeepAlive = true;
        UserName = primaryUser;
        StandardOutPath = "/tmp/loki.log";
        StandardErrorPath = "/tmp/loki.error.log";
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

    myConfig.serviceRegistry = commonLib.mkServiceRegistry "loki" {
      displayName = "Loki";
      port = cfg.port;
      label = "org.grafana.loki";
      errorLog = "/tmp/loki.error.log";
      enabled = cfg.enable;
    };
  };
}
