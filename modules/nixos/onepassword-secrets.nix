{
  config,
  pkgs,
  lib,
  ...
}:
with lib; let
  cfg = config.services.onepassword-secrets;
  secretsDir = "/run/opnix/secrets";
in {
  options.services.onepassword-secrets = {
    enable = mkEnableOption "Enable 1Password secrets management service";

    tokenFile = mkOption {
      type = types.str;
      default = "/etc/opnix-token";
      description = "Path to 1Password service account token file";
    };

    vault = mkOption {
      type = types.str;
      default = "Homelab";
      description = "1Password vault name containing secrets";
    };

    secrets = mkOption {
      type = types.attrsOf (types.submodule {
        options = {
          reference = mkOption {
            type = types.str;
            description = "1Password item reference (e.g., op://vault/item/field)";
          };
          owner = mkOption {
            type = types.str;
            description = "User who should own the secret file";
          };
          group = mkOption {
            type = types.str;
            default = "root";
            description = "Group who should own the secret file";
          };
          services = mkOption {
            type = types.listOf types.str;
            default = [];
            description = "Services that depend on this secret";
          };
          permissions = mkOption {
            type = types.str;
            default = "0600";
            description = "File permissions for the secret (octal format)";
          };
        };
      });
      default = {};
      description = "Secrets to fetch from 1Password";
    };
  };

  config = mkIf cfg.enable {
    # Create secrets directory
    systemd.tmpfiles.rules = [
      "d ${secretsDir} 0755 root root -"
    ];

    # Main 1Password secrets service
    systemd.services.onepassword-secrets = {
      description = "1Password secrets fetcher";
      after = ["network-online.target"];
      wants = ["network-online.target"];
      wantedBy = ["multi-user.target"];
      before = flatten (mapAttrsToList (_: secret: map (service: "${service}.service") secret.services) cfg.secrets);

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;

        ExecStartPre = "${pkgs.writeScript "check-op-token" ''
          #!${pkgs.bash}/bin/bash
          set -e

          if [[ ! -f "${cfg.tokenFile}" ]]; then
            echo "Error: 1Password service token file not found at ${cfg.tokenFile}"
            echo "Please run 'task 1password:service:setup' to generate the token"
            exit 1
          fi

          # Ensure token file has proper permissions
          chmod 600 "${cfg.tokenFile}"
          echo "1Password service token found and permissions verified"
        ''}";

        ExecStart = "${pkgs.writeScript "fetch-secrets" ''
          #!${pkgs.bash}/bin/bash
          set -e
          export OP_SERVICE_ACCOUNT_TOKEN=$(cat "${cfg.tokenFile}")

          echo "Fetching secrets from 1Password vault: ${cfg.vault}"

          # Fetch each secret and write to file with proper permissions
          ${concatStringsSep "\n" (mapAttrsToList (name: secret: ''
              echo "Fetching secret: ${name}"
              SECRET_VALUE=$(${pkgs._1password-cli}/bin/op read "${secret.reference}" 2>/dev/null || {
                echo "Error: Failed to fetch secret ${name} from ${secret.reference}"
                echo "Please check the reference and vault permissions"
                exit 1
              })

              echo "$SECRET_VALUE" > "${secretsDir}/${name}"
              chown "${secret.owner}:${secret.group}" "${secretsDir}/${name}"
              chmod "${secret.permissions}" "${secretsDir}/${name}"
              echo "Secret ${name} fetched successfully"
            '')
            cfg.secrets)}

          echo "All secrets fetched successfully"
        ''}";

        ExecStop = "${pkgs.writeScript "cleanup-secrets" ''
          #!${pkgs.bash}/bin/bash
          echo "Cleaning up secrets directory"
          rm -rf ${secretsDir}
        ''}";

        # Security settings
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ReadWritePaths = [secretsDir];
        ReadOnlyPaths = [cfg.tokenFile "/etc/ssl/certs"];
        NoNewPrivileges = true;
        MemoryDenyWriteExecute = true;
        RestrictRealtime = true;
        SystemCallFilter = ["@system-service" "~@privileged"];
        Restart = "on-failure";
        RestartSec = "30s";
      };

      # Environment
      environment = {
        OP_INTEGRATION_ID = "opnix";
        OP_BIOMETRIC_UNLOCK_ENABLED = "false";
      };
    };

    # Add 1Password CLI to system packages
    environment.systemPackages = with pkgs; [
      _1password-cli
    ];
  };
}
