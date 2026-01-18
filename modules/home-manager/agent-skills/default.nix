{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.myConfig.agent-skills;
  homeDir = config.home.homeDirectory;
in {
  imports = [
    ./skills.nix
    ./updates.nix
  ];
  options = {
    myConfig.agent-skills = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Enable agent skills management";
      };

      # Home-manager specific options
      skillsPath = mkOption {
        type = types.str;
        default = "${homeDir}/.config/opencode/skills";
        description = "Path where skills should be installed";
      };

      superpowersPath = mkOption {
        type = types.str;
        default = "${homeDir}/.config/opencode/superpowers/skills";
        description = "Path where superpowers skills should be installed";
      };
    };
  };

  config = mkIf cfg.enable {
    # Assertions for path validation
    assertions = [
      {
        assertion = lib.hasPrefix homeDir cfg.skillsPath;
        message = "agent-skills.skillsPath must be within home directory";
      }
      {
        assertion = lib.hasPrefix homeDir cfg.superpowersPath;
        message = "agent-skills.superpowersPath must be within home directory";
      }
    ];

    # Basic skills directory structure
    home.file."${cfg.skillsPath}/.keep" = {
      text = "";
    };

    home.file."${cfg.superpowersPath}/.keep" = {
      text = "";
    };

    # Home manager programs configuration
    programs.home-manager.enable = true;
  };
}
