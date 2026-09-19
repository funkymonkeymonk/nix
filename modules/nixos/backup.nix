# Centralized Restic backup policy for NixOS.
{
  config,
  lib,
  ...
}:
with lib; let
  cfg = config.myConfig.backup;
  backupPaths = map (entry: entry.path) cfg.paths;
  backupExcludes = concatLists (map (entry: map (exclude: "${entry.path}/${exclude}") entry.exclude) cfg.paths);
in {
  options.myConfig.backup = {
    enable = mkEnableOption "centralized Restic backups";

    paths = mkOption {
      type = types.listOf (types.submodule {
        options = {
          path = mkOption {
            type = types.path;
            description = "Directory or file to include in the backup";
          };

          exclude = mkOption {
            type = types.listOf types.str;
            default = [];
            description = "Paths relative to the entry to exclude";
          };
        };
      });
      default = [];
      description = "Backup paths contributed by enabled service modules";
    };

    repository = mkOption {
      type = types.str;
      default = "";
      description = "Restic repository URL";
    };

    passwordFile = mkOption {
      type = types.path;
      default = "/run/secrets/zero-restic-password";
      description = "Runtime file containing the Restic repository password";
    };

    environmentFile = mkOption {
      type = types.path;
      default = "/run/secrets/restic-r2.env";
      description = "Runtime environment file containing object-storage credentials";
    };

    accessKeyFile = mkOption {
      type = types.path;
      default = "/run/secrets/personal-backups-accesskey-id";
      description = "Runtime file containing the object-storage access key ID";
    };

    secretAccessKeyFile = mkOption {
      type = types.path;
      default = "/run/secrets/personal-backups-secret-access-key";
      description = "Runtime file containing the object-storage secret access key";
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.repository != "";
        message = "myConfig.backup.repository must be set when backups are enabled";
      }
      {
        assertion = cfg.paths != [];
        message = "myConfig.backup.paths must contain at least one path when backups are enabled";
      }
    ];

    services.restic.backups.zero = {
      inherit (cfg) repository passwordFile environmentFile;
      paths = backupPaths;
      exclude = backupExcludes;
      pruneOpts = [
        "--keep-daily 7"
        "--keep-weekly 4"
        "--keep-monthly 12"
      ];
      timerConfig = {
        OnCalendar = "daily";
        Persistent = true;
      };
    };

    systemd.services.restic-backup-env = {
      description = "Prepare Restic object-storage credentials";
      wantedBy = ["multi-user.target"];
      before = ["restic-backups-zero.service"];
      after = ["opnix-secrets.service"];
      requires = ["opnix-secrets.service"];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        access_key_file=${cfg.accessKeyFile}
        secret_key_file=${cfg.secretAccessKeyFile}
        environment_file=${cfg.environmentFile}
        for file in "$access_key_file" "$secret_key_file"; do
          if [ ! -r "$file" ]; then
            echo "Restic credential is missing: $file" >&2
            exit 1
          fi
        done
        install -d -m 0750 -o root -g root /run/secrets
        printf 'AWS_ACCESS_KEY_ID=%s\nAWS_SECRET_ACCESS_KEY=%s\n' \
          "$(cat "$access_key_file")" "$(cat "$secret_key_file")" > "$environment_file"
        chmod 0400 "$environment_file"
      '';
    };

    systemd.services.restic-backups-zero = {
      wants = ["restic-backup-env.service"];
      after = ["restic-backup-env.service"];
    };
  };
}
