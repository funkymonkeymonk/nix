{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.myConfig.agent-skills;

  # Default superpowers repo
  defaultRepo = "github:obra/superpowers";
  defaultVersion = "main";
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

      # Repository configuration
      skillsRepo = mkOption {
        type = types.str;
        default = defaultRepo;
        description = "Git repository containing agent skills";
      };

      skillsVersion = mkOption {
        type = types.str;
        default = defaultVersion;
        description = "Branch/tag/commit to use for skills";
      };

      # Home-manager specific options
      skillsPath = mkOption {
        type = types.str;
        default = "$HOME/.config/opencode/skills";
        description = "Path where skills should be installed";
      };

      superpowersPath = mkOption {
        type = types.str;
        default = "$HOME/.config/opencode/superpowers/skills";
        description = "Path where superpowers skills should be installed";
      };
    };
  };
}
