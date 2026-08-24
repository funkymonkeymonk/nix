# Prometheus Alertmanager for Darwin (macOS)
# Routes alerts fired by Prometheus's rule evaluation.
#
# OPEN ITEM (see PR description): the real notification receiver (Matrix or
# Discord webhook) is genuinely TBD — no credentials are available yet.
# This module wires up Alertmanager itself with a documented *null*
# receiver placeholder (drops alerts silently, no external calls) rather
# than guessing a webhook URL. Set `receiverWebhookUrl` once a real
# endpoint + credentials exist to route alerts there instead.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.myConfig.alertmanager;

  commonLib = import ../../common/lib.nix {inherit lib;};

  primaryUser = commonLib.primaryUser config;
  darwinHomeDir = commonLib.darwinHomeDir config;
  dataDir = cfg.dataDir;

  alertmanagerConfig = {
    route = {
      receiver = "null-receiver";
      group_by = ["alertname"];
      group_wait = "30s";
      group_interval = "5m";
      repeat_interval = "4h";
    };

    receivers =
      [
        # Null receiver: no integrations configured, so alerts routed here
        # are acknowledged but produce no notification. This is the safe
        # default until a real webhook is wired up (see module header).
        {name = "null-receiver";}
      ]
      ++ lib.optional (cfg.receiverWebhookUrl != null) {
        name = "webhook-receiver";
        webhook_configs = [{url = cfg.receiverWebhookUrl;}];
      };
  };

  configFile = pkgs.writeText "alertmanager.yml" (builtins.toJSON alertmanagerConfig);

  alertmanagerScript = pkgs.writeShellScript "alertmanager-launchd-service" ''
    set -euo pipefail

    mkdir -p "${dataDir}"

    exec ${pkgs.prometheus-alertmanager}/bin/alertmanager \
      --config.file ${configFile} \
      --storage.path "${dataDir}" \
      --web.listen-address=${cfg.bindAddress}:${toString cfg.port}
  '';
in {
  options.myConfig.alertmanager = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable Prometheus Alertmanager for alert routing/deduplication";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 9093;
      description = "Port for Alertmanager HTTP server";
    };

    bindAddress = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = "Bind address for Alertmanager HTTP server. Defaults to loopback-only since Prometheus queries it on the same host.";
    };

    dataDir = lib.mkOption {
      type = lib.types.str;
      default = "${darwinHomeDir}/Library/Application Support/Alertmanager";
      description = "Directory for Alertmanager silence/notification-log storage";
    };

    receiverWebhookUrl = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        Webhook URL for the real alert receiver (e.g. a Matrix or Discord
        incoming webhook). Genuinely TBD as of this module's introduction —
        no credentials are available. Leave null to route all alerts to a
        null receiver (silently dropped, no external calls) until a real
        endpoint is provisioned.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    launchd.daemons.alertmanager = {
      command = alertmanagerScript;
      serviceConfig = {
        Label = "org.prometheus.alertmanager";
        RunAtLoad = true;
        KeepAlive = true;
        UserName = primaryUser;
        StandardOutPath = "/tmp/alertmanager.log";
        StandardErrorPath = "/tmp/alertmanager.error.log";
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

    myConfig.serviceRegistry = commonLib.mkServiceRegistry "alertmanager" {
      displayName = "Alertmanager";
      port = cfg.port;
      label = "org.prometheus.alertmanager";
      errorLog = "/tmp/alertmanager.error.log";
      enabled = cfg.enable;
    };
  };
}
