{
  config,
  lib,
  ...
}: let
  cfg = config.myConfig.roles.agent-skills;
in {
  config = lib.mkIf cfg.enable {
    environment = {
      sessionVariables = {
        AGENT_SKILLS_PATH = "$HOME/.config/opencode/skills";
        SUPERPOWERS_SKILLS_PATH = "$HOME/.config/opencode/superpowers/skills";
      };
      variables = {
        AGENT_SKILLS_PATH = "$HOME/.config/opencode/skills";
        SUPERPOWERS_SKILLS_PATH = "$HOME/.config/opencode/superpowers/skills";
      };
    };

    environment.shellAliases = {
      skills-status = "ls -la $AGENT_SKILLS_PATH $SUPERPOWERS_SKILLS_PATH";
      skills-update = "devenv tasks run agent-skills:update";
      skills-list = "find $AGENT_SKILLS_PATH -name 'SKILL.md' -exec basename {} \\; | sort";
    };
  };
}
