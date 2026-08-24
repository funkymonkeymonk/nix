# myConfig.email-backup options — owned here, consumed by
# modules/home-manager/email-backup.nix (loaded conditionally via
# modules/common/users.nix) and set by modules/roles/email-backup.nix.
{lib, ...}: {
  options.myConfig.email-backup = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable encrypted immutable email backups (mbsync pull-only + restic + notmuch)";
    };

    accountName = lib.mkOption {
      type = lib.types.str;
      default = "gmail";
      description = "Name for the email account (used in Maildir subdirectory and backup tags)";
    };

    imapHost = lib.mkOption {
      type = lib.types.str;
      default = "imap.gmail.com";
      description = "IMAP server hostname";
    };

    imapPort = lib.mkOption {
      type = lib.types.port;
      default = 993;
      description = "IMAP server port";
    };

    username = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "Username for launchd/systemd service environment (required on Darwin)";
    };

    backupInterval = lib.mkOption {
      type = lib.types.int;
      default = 3600;
      description = "Backup interval in seconds (default: 3600 = 1 hour). Minimum recommended: 900 (15 min).";
    };

    maildir = lib.mkOption {
      type = lib.types.str;
      default = ".mail-backup";
      description = "Maildir staging path relative to home directory (ephemeral, used for sync before restic snapshot)";
    };

    resticRepo = lib.mkOption {
      type = lib.types.str;
      default = ".local/share/email-backup/restic-repo";
      description = "Restic repository path relative to home directory. Can also be s3:, b2:, sftp:, or rest: URLs for remote storage.";
    };

    resticPasswordFile = lib.mkOption {
      type = lib.types.str;
      default = ".config/email-backup/restic-password";
      description = "Path relative to home directory containing the restic repository password";
    };

    retentionDays = lib.mkOption {
      type = lib.types.int;
      default = 365;
      description = "Number of days to keep daily snapshots (default: 365). Hourly snapshots kept for 7 days.";
    };

    notmuchTags = {
      new = lib.mkOption {
        type = lib.types.str;
        default = "new";
        description = "Tag applied to new messages by notmuch";
      };

      exclude = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = ["deleted" "spam"];
        description = "Tags to exclude from search results by default";
      };
    };
  };
}
