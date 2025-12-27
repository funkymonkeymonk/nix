{
  config,
  pkgs,
  lib,
  ...
}:
with lib; let
  cfg = config.services.linkwarden;
in {
  options.services.linkwarden = {
    enable = mkEnableOption "Enable Linkwarden bookmark manager service";

    package = mkOption {
      type = types.package;
      default = pkgs.unstable.linkwarden;
      description = "Linkwarden package to use";
    };

    user = mkOption {
      type = types.str;
      default = "linkwarden";
      description = "User account under which Linkwarden runs";
    };

    group = mkOption {
      type = types.str;
      default = "linkwarden";
      description = "Group account under which Linkwarden runs";
    };

    dataDir = mkOption {
      type = types.str;
      default = "/var/lib/linkwarden";
      description = "Directory where Linkwarden stores its data";
    };

    port = mkOption {
      type = types.int;
      default = 3000;
      description = "Port on which Linkwarden listens";
    };

    openFirewall = mkOption {
      type = types.bool;
      default = true;
      description = "Whether to open the Linkwarden port in the firewall";
    };

    environment = mkOption {
      type = types.attrsOf types.str;
      default = {};
      description = "Additional environment variables for Linkwarden";
    };
  };

  config = mkIf cfg.enable {
    # Create system user for Linkwarden
    users.users.${cfg.user} = {
      isSystemUser = true;
      inherit (cfg) group;
      description = "Linkwarden service user";
    };

    users.groups.${cfg.group} = {};

    # Create data directory with proper permissions
    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0755 ${cfg.user} ${cfg.group} -"
    ];

    # Systemd service configuration
    systemd.services.linkwarden = {
      description = "Linkwarden bookmark manager";
      after = ["postgresql.service" "network.target" "set-postgres-passwords.service"] ++ optional config.services.meilisearch.enable "meilisearch.service";
      wants = ["postgresql.service" "set-postgres-passwords.service"] ++ optional config.services.meilisearch.enable "meilisearch.service";
      wantedBy = ["multi-user.target"];

      serviceConfig = {
        Type = "simple";
        User = cfg.user;
        Group = cfg.group;
        WorkingDirectory = cfg.dataDir;
        ExecStartPre = "${pkgs.writeScript "linkwarden-migrate" ''
          #!${pkgs.bash}/bin/bash
          set -e

          # Wait for database to be ready and have password set
          echo "Waiting for database to be ready..."
          until ${pkgs.postgresql}/bin/pg_isready -h localhost -p 5432 -U linkwarden; do
            echo "Database not ready, waiting..."
            sleep 5
          done

          # Run database migrations if needed
          echo "Running database migrations..."
          cd ${cfg.package}
          # Linkwarden uses Prisma, check if we need to run migrations
          if [[ -d "${cfg.package}/prisma" ]]; then
            ${pkgs.nodejs}/bin/npx prisma migrate deploy --schema "${cfg.package}/prisma/schema.prisma" || echo "Migrations may have already run or no migrations needed"
          fi

          echo "Database setup completed"
        ''}";
        ExecStart = "${cfg.package}/bin/linkwarden start";
        ExecReload = "${pkgs.coreutils}/bin/kill -HUP $MAINPID";
        Restart = "on-failure";
        RestartSec = "10s";
        TimeoutSec = "30";

        # Security settings
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ReadWritePaths = [cfg.dataDir "/var/cache/linkwarden"];
      };

      # Environment variables
      environment =
        {
          DATABASE_URL = "postgresql://linkwarden:${config.services.onepassword-secrets.secrets.linkwardenDbPassword.value or ""}@localhost:5432/linkwarden";
          NEXTAUTH_SECRET = config.services.onepassword-secrets.secrets.nextauthSecret.value or "";
          NEXTAUTH_URL = "http://drlight:${toString cfg.port}/api/v1/auth";
          PORT = toString cfg.port;
          MEILI_HOST = "http://localhost:7700";
          MEILI_MASTER_KEY = config.services.onepassword-secrets.secrets.meilisearchKey.value or "";
        }
        // cfg.environment;
    };

    # Firewall configuration
    networking.firewall.allowedTCPPorts = lib.optionals cfg.openFirewall [cfg.port];

    # Add Linkwarden to system packages (for CLI tools)
    environment.systemPackages = [cfg.package];
  };
}
