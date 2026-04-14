# Email backup role - immutable encrypted email backups with search
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.myConfig.roles.email-backup;
in {
  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      isync # mbsync - IMAP to Maildir pull-only sync
      notmuch # Mail indexer and search for backup archive
      restic # Encrypted, deduplicated, immutable backups
    ];

    myConfig.email-backup.enable = true;
  };
}
