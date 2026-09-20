{
  config,
  lib,
  ...
}: {
  options.myConfig.backup = {
    enable = lib.mkEnableOption "system backups";
    repository = lib.mkOption {type = lib.types.str;};
    paths = lib.mkOption {type = lib.types.listOf lib.types.str;};
  };
  config = lib.mkIf config.myConfig.backup.enable {
    services.restic.backups.media = {
      inherit (config.myConfig.backup) repository paths;
      passwordFile = "/run/secrets/drlight-restic-password";
    };
  };
}
