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

    # Create data and cache directories with proper permissions
    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0755 ${cfg.user} ${cfg.group} -"
      "d /var/cache/linkwarden 0755 ${cfg.user} ${cfg.group} -"
    ];

    # Systemd service configuration
    systemd.services.linkwarden = {
      description = "Linkwarden bookmark manager";
      after = ["postgresql.service" "network.target" "opnix-secrets.service" "set-postgres-passwords.service"] ++ optional config.services.meilisearch.enable "meilisearch.service";
      wants = ["postgresql.service" "opnix-secrets.service" "set-postgres-passwords.service"] ++ optional config.services.meilisearch.enable "meilisearch.service";
      wantedBy = ["multi-user.target"];

      serviceConfig = {
        Type = "simple";
        User = cfg.user;
        Group = cfg.group;
        WorkingDirectory = cfg.dataDir;
        ExecStartPre = "${pkgs.writeScript "linkwarden-prep" ''
          #!${pkgs.bash}/bin/bash
          set -e

          # Wait for secrets to be populated
          echo "Waiting for secrets to be populated..."
          timeout=60
          count=0
          while [[ $count -lt $timeout ]] && [[ ! -f "/run/opnix/secrets/linkwardenDbPassword" ]]; do
            echo "Waiting for linkwarden database password secret... ($count/$timeout)"
            sleep 1
            count=$((count + 1))
          done

          if [[ $count -ge $timeout ]]; then
            echo "ERROR: Timeout waiting for secrets after $timeout seconds"
            exit 1
          fi

          # Read secrets (only linkwarden's own secrets)
          DB_PASSWORD=$(cat /run/opnix/secrets/linkwardenDbPassword)
          NEXTAUTH_SECRET=$(cat /run/opnix/secrets/nextauthSecret)
          MEILI_KEY=$(cat /run/opnix/secrets/meilisearchKey)

          # Create environment file
          echo "DATABASE_URL=postgresql://linkwarden:$DB_PASSWORD@localhost:5432/linkwarden" > /tmp/linkwarden-env
          echo "NEXTAUTH_SECRET=$NEXTAUTH_SECRET" >> /tmp/linkwarden-env
          echo "NEXTAUTH_URL=http://drlight:${toString cfg.port}/api/v1/auth" >> /tmp/linkwarden-env
          echo "PORT=${toString cfg.port}" >> /tmp/linkwarden-env
          echo "MEILI_HOST=http://localhost:7700" >> /tmp/linkwarden-env
          echo "MEILI_MASTER_KEY=$MEILI_KEY" >> /tmp/linkwarden-env

          echo "Linkwarden environment file created at /tmp/linkwarden-env"

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
        ExecStart = "${pkgs.writeScript "linkwarden-start" ''
          #!/bin/sh
          set -e

          # Load environment if file exists
          if [[ -f /run/linkwarden-env ]]; then
            set -a
            source /run/linkwarden-env
          fi

          # Wait for secrets to be populated (with timeout)
          echo "Waiting for secrets to be populated..."
          timeout=60
          count=0
          while [[ $count -lt $timeout ]] && [[ ! -f "/run/opnix/secrets/linkwardenDbPassword" ]]; do
            echo "Waiting for linkwarden database password secret... ($count/$timeout)"
            sleep 1
            count=$((count + 1))
          done

          if [[ $count -ge $timeout ]]; then
            echo "ERROR: Timeout waiting for secrets after $timeout seconds"
            exit 1
          fi

          while [[ ! -f "/run/opnix/secrets/nextauthSecret" ]]; do
            echo "Waiting for nextauth secret..."
            sleep 1
          done

          # Read only linkwarden's own secrets (NO meilisearch access needed)
          DB_PASSWORD=$(cat /run/opnix/secrets/linkwardenDbPassword)
          NEXTAUTH_SECRET=$(cat /run/opnix/secrets/nextauthSecret)
          MEILI_KEY="''${MEILI_MASTER_KEY:-""}"

          # Create environment file
          echo "DATABASE_URL=postgresql://linkwarden:$DB_PASSWORD@localhost:5432/linkwarden" > /tmp/linkwarden-env
          echo "NEXTAUTH_SECRET=$NEXTAUTH_SECRET" >> /tmp/linkwarden-env
          echo "NEXTAUTH_URL=http://drlight:${toString cfg.port}/api/v1/auth" >> /tmp/linkwarden-env
          echo "PORT=${toString cfg.port}" >> /tmp/linkwarden-env
          echo "MEILI_HOST=http://localhost:7700" >> /tmp/linkwarden-env
          echo "MEILI_MASTER_KEY=$MEILI_KEY" >> /tmp/linkwarden-env

          echo "Linkwarden environment file created at /tmp/linkwarden-env"

          # Source the environment file
          set -a
          source /tmp/linkwarden-env

          # Run database migrations if needed
          echo "Running database migrations..."
          cd ${cfg.package}
          # Linkwarden uses Prisma, check if we need to run migrations
          if [[ -d "${cfg.package}/prisma" ]]; then
            ${pkgs.nodejs}/bin/npx prisma migrate deploy --schema "${cfg.package}/prisma/schema.prisma" || echo "Migrations may have already run or no migrations needed"
          fi

          echo "Database setup completed"
          # Override the npm script to bind to all interfaces
          cd ${cfg.package}/share/linkwarden/apps/web
          exec ${pkgs.nodejs}/bin/node node_modules/.bin/next start -H 0.0.0.0 -p ${toString cfg.port}
        ''}";
        ExecReload = "${pkgs.coreutils}/bin/kill -HUP $MAINPID";
        Restart = "on-failure";
        RestartSec = "10s";
        TimeoutSec = "30";

        # Security settings
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ReadWritePaths = [cfg.dataDir "/var/cache/linkwarden" "/run"];

        # Environment file for secrets (created in ExecStartPre, not systemd)
        # EnvironmentFile = "/run/linkwarden-env";
      };

      # Environment variables (fallbacks)
      environment =
        {
          NEXTAUTH_URL = "http://drlight:${toString cfg.port}/api/v1/auth";
          PORT = toString cfg.port;
          HOST = "0.0.0.0";
          MEILI_HOST = "http://localhost:7700";
        }
        // cfg.environment;
    };

    # Firewall configuration
    networking.firewall.allowedTCPPorts = lib.optionals cfg.openFirewall [cfg.port];

    # Add Linkwarden to system packages (for CLI tools)
    environment.systemPackages = [cfg.package];
  };
}
