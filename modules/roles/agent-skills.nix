{
  config,
  lib,
  ...
}: let
  cfg = config.myConfig.roles.agent-skills;
in {
  options.myConfig.roles.agent-skills.enable = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = "Shell aliases for listing and updating the installed personal skills";
  };

  config = lib.mkIf cfg.enable {
    environment = lib.mkMerge [
      {
        variables = {
          AGENT_SKILLS_PATH = "$HOME/.agents/skills";
        };
        shellAliases = {
          skills-status = "ls -la $AGENT_SKILLS_PATH";
          skills-update = "nix flake update personal-skills";
          skills-list = "find $AGENT_SKILLS_PATH -name 'SKILL.md' -exec basename {} \\; | sort";
        };
      }
      (lib.optionalAttrs (builtins.hasAttr "sessionVariables" config.environment) {
        sessionVariables = {
          AGENT_SKILLS_PATH = "$HOME/.agents/skills";
        };
      })
    ];
  };
}
