{
  config,
  pkgs,
  lib,
  ...
}:
with lib; let
  cfg = config.services.meilisearch;
in {
  options.services.meilisearch = {
    enable = mkEnableOption "Enable Meilisearch search service";

    package = mkOption {
      type = types.package;
      default = pkgs.unstable.meilisearch;
      description = "Meilisearch package to use";
    };

    user = mkOption {
      type = types.str;
      default = "meilisearch";
      description = "User account under which Meilisearch runs";
    };

    group = mkOption {
      type = types.str;
      default = "meilisearch";
      description = "Group account under which Meilisearch runs";
    };

    dataDir = mkOption {
      type = types.str;
      default = "/var/lib/meilisearch";
      description = "Directory where Meilisearch stores its data";
    };

    environment = mkOption {
      type = types.attrsOf types.str;
      default = {};
      description = "Additional environment variables for Meilisearch";
    };

    backupInterval = mkOption {
      type = types.str;
      default = "daily";
      description = "Backup frequency for Meilisearch indexes";
    };

    maxIndexingMemory = mkOption {
      type = types.str;
      default = "256M";
      description = "Maximum memory for indexing operations";
    };

    maxIndexingThreads = mkOption {
      type = types.int;
      default = 4;
      description = "Maximum threads for indexing operations";
    };
  };

  config = mkIf cfg.enable {
    # Create system user for Meilisearch
    users.users.${cfg.user} = {
      isSystemUser = true;
      inherit (cfg) group;
      description = "Meilisearch service user";
    };

    users.groups.${cfg.group} = {};

    # Systemd configuration
    systemd = {
      # Create data and backup directories with proper permissions
      tmpfiles.rules = [
        "d ${cfg.dataDir} 0755 ${cfg.user} ${cfg.group} -"
        "d ${cfg.dataDir}/backups 0755 ${cfg.user} ${cfg.group} -"
      ];

      # Systemd service configuration
      services.meilisearch = {
        description = "Meilisearch search engine";
        after = ["network.target"] ++ optional config.services.postgresql.enable "postgresql.service";
        wants = ["network.target"] ++ optional config.services.postgresql.enable "postgresql.service";
        wantedBy = ["multi-user.target"];

        serviceConfig = {
          Type = "simple";
          User = cfg.user;
          Group = cfg.group;
          WorkingDirectory = cfg.dataDir;
          ExecStart = "${cfg.package}/bin/meilisearch";
          ExecReload = "${pkgs.coreutils}/bin/kill -HUP $MAINPID";
          Restart = "on-failure";
          RestartSec = "15s";
          TimeoutSec = "60";

          # Security settings
          PrivateTmp = true;
          ProtectSystem = "strict";
          ProtectHome = true;
          ReadWritePaths = [cfg.dataDir "${cfg.dataDir}/backups"];
          ReadOnlyPaths = ["/etc/ssl/certs"];

          # Resource limits
          MemoryMax = "512M";
          CPUQuota = "50%";
        };

        # Environment variables
        environment =
          {
            MEILI_MASTER_KEY = "$(cat /run/opnix/secrets/meilisearchKey)";
            MEILI_ENV = "production";
            MEILI_DB_ENGINE = "postgres";
            MEILI_DB_URL = "postgres://meilisearch:$(cat /run/opnix/secrets/meilisearchDbPassword)@localhost:5432/meilisearch";
            MEILI_DATA_DIR = cfg.dataDir;
            MEILI_LOG_LEVEL = "INFO";
            MEILI_MAX_INDEXING_MEMORY = cfg.maxIndexingMemory;
            MEILI_MAX_INDEXING_THREADS = toString cfg.maxIndexingThreads;
          }
          // cfg.environment;
      };

      # Backup service for Meilisearch indexes
      services.meilisearch-backup = {
        description = "Backup Meilisearch indexes";
        startAt = cfg.backupInterval;
        after = ["meilisearch.service"];
        requires = ["meilisearch.service"];

        serviceConfig = {
          Type = "oneshot";
          User = cfg.user;
          Group = cfg.group;
          ExecStart = "${pkgs.coreutils}/bin/mkdir -p ${cfg.dataDir}/backups && ${pkgs.coreutils}/bin/cp -r ${cfg.dataDir}/data.mdb ${cfg.dataDir}/backups/data-$(date +%%Y-%%m-%%d-%%H%%M%%S).mdb";
          PrivateTmp = true;
        };
      };
    };

    # Add Meilisearch to system packages (for CLI tools)
    environment.systemPackages = [cfg.package];
  };
}
