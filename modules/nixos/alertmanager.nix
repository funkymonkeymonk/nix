# Prometheus Alertmanager for NixOS (type-server).
#
# OPEN ITEM: the real notification receiver (Matrix or Discord webhook) is
# genuinely TBD — no credentials are available. This module wires up
# Alertmanager itself with a documented *null* receiver placeholder (drops
# alerts silently, no external calls) rather than guessing a webhook URL,
# matching the pattern established for darwin-server's Alertmanager in
# modules/services/alertmanager/darwin.nix (PR #432). Set
# `receiverWebhookUrl` once a real endpoint + credentials exist to route
# alerts there instead.
#
# Alerts themselves (service down, high memory, low disk) are evaluated by
# Prometheus — see modules/nixos/prometheus.nix — and routed here.
#
# See tests/test-nixos-observability.nix for coverage.
{
  config,
  lib,
  ...
}:
with lib; let
  cfg = config.myConfig.alertmanager;

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
      ++ optional (cfg.receiverWebhookUrl != null) {
        name = "webhook-receiver";
        webhook_configs = [{url = cfg.receiverWebhookUrl;}];
      };
  };
in {
  options.myConfig.alertmanager = {
    enable = mkEnableOption "Prometheus Alertmanager for alert routing/deduplication";

    port = mkOption {
      type = types.port;
      default = 9093;
      description = "Port for Alertmanager HTTP server.";
    };

    receiverWebhookUrl = mkOption {
      type = types.nullOr types.str;
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

  config = mkIf cfg.enable {
    services.prometheus.alertmanager = {
      enable = true;
      port = cfg.port;
      configuration = alertmanagerConfig;
    };
  };
}
