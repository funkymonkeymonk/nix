{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.myConfig.agent-skills;
in {
  options.myConfig.agent-skills = {
    enable = mkEnableOption "Agent skills management";
    skillsPath = mkOption {
      type = types.str;
      default = "${config.home.homeDirectory}/.config/opencode/skills";
      description = "Path where skills should be installed";
    };
    superpowersPath = mkOption {
      type = types.str;
      default = "${config.home.homeDirectory}/.config/opencode/superpowers/skills";
      description = "Path where superpowers skills should be installed";
    };
  };

  config = mkIf cfg.enable {
    # Module implementation will be added in next task
  };
}
