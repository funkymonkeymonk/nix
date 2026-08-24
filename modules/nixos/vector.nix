# Vector log shipper for NixOS.
#
# Reads system logs from journald, attaches host/service/severity labels via
# a VRL remap transform, and forwards them to a Loki sink over HTTP.
#
# See tests/test-log-aggregator.nix for coverage.
{
  config,
  lib,
  ...
}:
with lib; let
  cfg = config.myConfig.vector;
in {
  options.myConfig.vector = {
    enable = mkEnableOption "Vector log shipper (journald -> Loki)";

    lokiEndpoint = mkOption {
      type = types.str;
      default = "http://localhost:3100";
      description = "Base URL of the Loki instance Vector ships logs to.";
    };

    defaultService = mkOption {
      type = types.str;
      default = config.networking.hostName;
      description = ''
        Fallback value for the Loki "service" label when a journal entry has
        neither SYSLOG_IDENTIFIER nor _SYSTEMD_UNIT set.
      '';
    };
  };

  config = mkIf cfg.enable {
    services.vector = {
      enable = true;
      # Required for the journald source to read the system journal.
      journaldAccess = true;

      settings = {
        sources.journald = {
          type = "journald";
          current_boot_only = false;
        };

        # Derive the "service" and "severity" labels from journal fields so
        # the Loki sink below can attach them as query-able labels.
        transforms.add_log_labels = {
          type = "remap";
          inputs = ["journald"];
          source = ''
            .service = if exists(.SYSLOG_IDENTIFIER) {
              to_string(.SYSLOG_IDENTIFIER) ?? "${cfg.defaultService}"
            } else if exists(._SYSTEMD_UNIT) {
              to_string(._SYSTEMD_UNIT) ?? "${cfg.defaultService}"
            } else {
              "${cfg.defaultService}"
            }
            .severity = if exists(.PRIORITY) {
              to_syslog_level(to_int(.PRIORITY) ?? 6) ?? "info"
            } else {
              "info"
            }
          '';
        };

        sinks.loki = {
          type = "loki";
          inputs = ["add_log_labels"];
          endpoint = cfg.lokiEndpoint;
          encoding.codec = "json";
          # Acceptance criteria: log labels host, service, severity.
          # "host" is static (known at eval time); "service" and "severity"
          # are per-event, populated by the remap transform above.
          labels = {
            host = config.networking.hostName;
            service = "{{ service }}";
            severity = "{{ severity }}";
          };
        };
      };
    };
  };
}
