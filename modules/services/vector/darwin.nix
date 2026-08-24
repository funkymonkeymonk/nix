# Vector log shipper for Darwin (macOS)
# Tails this repo's launchd service log convention (/tmp/<service>.log and
# /tmp/<service>.error.log, set by every darwin.nix service module's
# StandardOutPath/StandardErrorPath) and ships them to Loki.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.myConfig.vector;

  commonLib = import ../../common/lib.nix {inherit lib;};

  primaryUser = commonLib.primaryUser config;
  darwinHomeDir = commonLib.darwinHomeDir config;
  dataDir = cfg.dataDir;

  lokiEndpoint = "http://${config.myConfig.loki.bindAddress}:${toString config.myConfig.loki.port}";

  vectorConfig = {
    data_dir = dataDir;

    sources.service_logs = {
      type = "file";
      include = cfg.logGlobs;
      read_from = "beginning";
    };

    sinks.loki = {
      type = "loki";
      inputs = ["service_logs"];
      endpoint = lokiEndpoint;
      encoding.codec = "text";
      labels = {
        job = "vector";
        host = cfg.hostLabel;
        filename = "{{ file }}";
      };
    };
  };

  configFile = pkgs.writeText "vector.yaml" (builtins.toJSON vectorConfig);

  vectorScript = pkgs.writeShellScript "vector-launchd-service" ''
    set -euo pipefail

    mkdir -p "${dataDir}"

    exec ${pkgs.vector}/bin/vector \
      --config ${configFile}
  '';
in {
  options.myConfig.vector = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable Vector log shipper (tails local service logs, ships to Loki)";
    };

    logGlobs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = ["/tmp/*.log"];
      description = "Glob patterns for log files to tail. Matches this repo's launchd StandardOutPath/StandardErrorPath convention (/tmp/<service>.log, /tmp/<service>.error.log).";
    };

    hostLabel = lib.mkOption {
      type = lib.types.str;
      default = "darwin-server";
      description = "Value for the 'host' label attached to all shipped log lines";
    };

    dataDir = lib.mkOption {
      type = lib.types.str;
      default = "${darwinHomeDir}/Library/Application Support/Vector";
      description = "Directory for Vector's file-tailing checkpoint state";
    };
  };

  config = lib.mkIf cfg.enable {
    launchd.daemons.vector = {
      command = vectorScript;
      serviceConfig = {
        Label = "com.datadoghq.vector";
        RunAtLoad = true;
        KeepAlive = true;
        UserName = primaryUser;
        StandardOutPath = "/tmp/vector.log";
        StandardErrorPath = "/tmp/vector.error.log";
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

    myConfig.serviceRegistry = commonLib.mkServiceRegistry "vector" {
      displayName = "Vector";
      port = 0;
      label = "com.datadoghq.vector";
      errorLog = "/tmp/vector.error.log";
      enabled = cfg.enable;
    };
  };
}
