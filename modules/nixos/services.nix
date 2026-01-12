{
  config,
  lib,
  pkgs,
  ...
}: {
  # Services configuration
  services = {
    # Jellyfin media server
    jellyfin = {
      enable = true;
      package = pkgs.unstable.jellyfin;
      openFirewall = true;
    };

    # Mealie recipe manager
    mealie = {
      enable = true;
      database.createLocally = true;
      port = 9000;
    };

    # PostgreSQL database server
    postgresql = {
      enable = true;
      package = pkgs.postgresql_16;
      ensureDatabases = ["linkwarden" "meilisearch"];
      ensureUsers = [
        {
          name = "linkwarden";
          ensureDBOwnership = true;
        }
        {
          name = "meilisearch";
          ensureDBOwnership = true;
        }
      ];

      # Authentication is handled through password setting service

      # Note: Passwords for service users will be managed through OpNix
      # The PostgreSQL users are created via ensureUsers above
    };
  };

  # Service to set database passwords from OpNix secrets
  systemd.services.set-postgres-passwords = {
    description = "Set PostgreSQL passwords from OpNix secrets";
    after = ["postgresql.service" "opnix-secrets.service"];
    wants = ["postgresql.service" "opnix-secrets.service"];
    serviceConfig = {
      Type = "oneshot";
      User = "postgres";
      RemainAfterExit = true;
      ExecStart = "${pkgs.writeScript "set-postgres-passwords" ''
        #!${pkgs.bash}/bin/bash
        set -e

        # Wait for PostgreSQL to be ready
        until ${pkgs.postgresql_16}/bin/pg_isready -h localhost -p 5432; do
          echo "Waiting for PostgreSQL to start..."
          sleep 2
        done

        # Set passwords from OpNix secrets
        if [[ -f /run/opnix/secrets/linkwardenDbPassword ]]; then
          LINKWARDEN_PASSWORD=$(cat /run/opnix/secrets/linkwardenDbPassword)
          ${pkgs.postgresql_16}/bin/psql -v ON_ERROR_STOP=1 -U postgres -d postgres -c "ALTER USER linkwarden PASSWORD '$LINKWARDEN_PASSWORD';"
          echo "Set password for linkwarden user"
        fi

        if [[ -f /run/opnix/secrets/meilisearchDbPassword ]]; then
          MEILISEARCH_PASSWORD=$(cat /run/opnix/secrets/meilisearchDbPassword)
          ${pkgs.postgresql_16}/bin/psql -v ON_ERROR_STOP=1 -U postgres -d postgres -c "ALTER USER meilisearch PASSWORD '$MEILISEARCH_PASSWORD';"
          echo "Set password for meilisearch user"
        fi
      ''}";
    };
  };
}
