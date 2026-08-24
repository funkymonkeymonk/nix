# Loki log storage backend for NixOS.
#
# Single-tenant, filesystem-backed Loki instance intended to receive logs
# shipped by modules/nixos/vector.nix. Uses the TSDB index + local
# filesystem chunk store — no external object storage required.
#
# See tests/test-log-aggregator.nix for coverage.
{
  config,
  lib,
  ...
}:
with lib; let
  cfg = config.myConfig.loki;
in {
  options.myConfig.loki = {
    enable = mkEnableOption "Loki log storage backend";

    port = mkOption {
      type = types.port;
      default = 3100;
      description = "HTTP port Loki listens on for log pushes and queries.";
    };

    dataDir = mkOption {
      type = types.path;
      default = "/var/lib/loki";
      description = "Directory Loki uses to store chunks, indexes, and the WAL.";
    };

    openFirewall = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Whether to open the firewall for Loki's HTTP port. Keep disabled
        (the default) when only local log shippers (e.g. Vector on the
        same host) push to Loki over localhost.
      '';
    };
  };

  config = mkIf cfg.enable {
    services.loki = {
      enable = true;
      dataDir = cfg.dataDir;

      configuration = {
        auth_enabled = false;

        server.http_listen_port = cfg.port;

        common = {
          path_prefix = cfg.dataDir;
          storage.filesystem = {
            chunks_directory = "${cfg.dataDir}/chunks";
            rules_directory = "${cfg.dataDir}/rules";
          };
          replication_factor = 1;
          ring.kvstore.store = "inmemory";
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

        limits_config = {
          reject_old_samples = true;
          reject_old_samples_max_age = "168h";
        };
      };
    };

    networking.firewall.allowedTCPPorts = mkIf cfg.openFirewall [cfg.port];
  };
}
