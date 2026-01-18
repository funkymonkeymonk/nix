{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.myConfig.agent-skills;
  homeDir = config.home.homeDirectory;
in {
  config = lib.mkIf cfg.enable {
    # Assertions for path validation and conflict checking
    assertions = [
      {
        assertion = lib.hasPrefix homeDir cfg.skillsPath;
        message = "agent-skills.skillsPath must be within home directory";
      }
      {
        assertion = lib.hasPrefix homeDir cfg.superpowersPath;
        message = "agent-skills.superpowersPath must be within home directory";
      }
      {
        assertion = cfg.skillsPath != cfg.superpowersPath;
        message = "agent-skills.skillsPath and superpowersPath must be different paths";
      }
      {
        assertion = !lib.hasSuffix "/" cfg.skillsPath;
        message = "agent-skills.skillsPath must not end with trailing slash";
      }
      {
        assertion = !lib.hasSuffix "/" cfg.superpowersPath;
        message = "agent-skills.superpowersPath must not end with trailing slash";
      }
      {
        assertion = lib.hasPrefix "${homeDir}/.config/" cfg.skillsPath;
        message = "agent-skills.skillsPath should be under .config directory for consistency";
      }
      {
        assertion = lib.hasPrefix "${homeDir}/.config/" cfg.superpowersPath;
        message = "agent-skills.superpowersPath should be under .config directory for consistency";
      }
    ];

    # Create skills directories with proper error handling
    home.file."${cfg.skillsPath}/.keep" = {
      text = "";
    };

    home.file."${cfg.superpowersPath}/.keep" = {
      text = "";
    };
  };
}
