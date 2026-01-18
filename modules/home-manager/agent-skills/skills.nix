{
  lib,
  pkgs,
  config,
  ...
}: let
  cfg = config.myConfig.agent-skills;

  # Function to safely read directory if it exists
  safeReadDir = path:
    if builtins.pathExists path && builtins.dirOf path != ""
    then builtins.readDir path
    else {};

  # Get skills from repository if the directory exists
  repoSkillsDir = ../agent-skills/skills;
  repoSkills = lib.attrNames (safeReadDir repoSkillsDir);

  # Helper to create skill file attribute
  mkSkillFile = skillName: destPath: {
    name = "${destPath}/${skillName}";
    value = {
      source = "${repoSkillsDir}/${skillName}";
      recursive = true;
    };
  };
in {
  config = lib.mkIf cfg.enable {
    # Combine all file assignments
    home.file =
      # Directory keep files
      {
        "${cfg.skillsPath}/.keep" = {
          text = "";
          onChange = "mkdir -p ${cfg.skillsPath}";
        };

        "${cfg.superpowersPath}/.keep" = {
          text = "";
          onChange = "mkdir -p ${cfg.superpowersPath}";
        };
      }
      //
      # Skills from repository to skills path
      lib.listToAttrs (
        map
        (skillName: mkSkillFile skillName cfg.skillsPath)
        repoSkills
      )
      //
      # Also install to superpowers path for compatibility
      lib.listToAttrs (
        map
        (skillName: mkSkillFile skillName cfg.superpowersPath)
        repoSkills
      );
  };
}
