{
  config,
  lib,
  ...
}: let
  cfg = config.myConfig.roles.agent-skills;
in {
  config = lib.mkIf cfg.enable {
    environment = lib.mkMerge [
      {
        variables = {
          AGENT_SKILLS_PATH = "$HOME/.config/opencode/skills";
          SUPERPOWERS_SKILLS_PATH = "$HOME/.config/opencode/superpowers/skills";
        };
        shellAliases = {
          skills-status = "ls -la $AGENT_SKILLS_PATH $SUPERPOWERS_SKILLS_PATH";
          skills-update = "devenv tasks run agent-skills:update";
          skills-list = "find $AGENT_SKILLS_PATH -name 'SKILL.md' -exec basename {} \\; | sort";
        };
      }
      (lib.optionalAttrs (builtins.hasAttr "sessionVariables" config.environment) {
        sessionVariables = {
          AGENT_SKILLS_PATH = "$HOME/.config/opencode/skills";
          SUPERPOWERS_SKILLS_PATH = "$HOME/.config/opencode/superpowers/skills";
        };
      })
    ];
  };
}
