# Canonical skill installation location — ~/.agents/skills/<name>/SKILL.md
#
# Follows the vendor-neutral Agent Skills convention (agentskills.io), not
# any single agent's own path. Both OpenCode and Pi discover
# ~/.agents/skills/<name>/SKILL.md natively with zero additional config
# (see https://opencode.ai/docs/skills and pi-mono's skills.md docs).
#
# This module installs every skill from the pinned personal skills repository
# once, regardless of which combination of opencode/claude/pi roles are
# enabled. Agent integrations use this shared location where supported.
#
# Gated on explicit skill-consuming roles, not foundation or shell-helper roles.
# The resolved skill set is shared across agents, so it does not belong inside
# opencode.nix, claude-code.nix, or pi-coding-agent.nix.
{
  osConfig,
  lib,
  ...
}: let
  skillsCfg = osConfig.myConfig.skills or {};
  skillConsumerRoles = ["developer" "creative" "workstation" "opencode" "claude" "pi"];
  hasSkillConsumerRole = lib.any (role: lib.elem role skillConsumerRoles) (skillsCfg.enabledRoles or []);
  hmLib = import ../lib.nix {inherit lib;};

  inherit
    (hmLib.mkFullSkillDirs {
      enabledRoles = skillsCfg.enabledRoles or [];
      skillsRepo = skillsCfg.repository or null;
    })
    skillDirs
    ;
in {
  config = lib.mkIf hasSkillConsumerRole {
    home.file =
      lib.mapAttrs' (
        name: dir:
          lib.nameValuePair ".agents/skills/${name}" {
            source = dir;
          }
      )
      skillDirs;
  };
}
