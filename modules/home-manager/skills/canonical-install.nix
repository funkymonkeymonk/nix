# Canonical skill installation location — ~/.agents/skills/<name>/SKILL.md
#
# Follows the vendor-neutral Agent Skills convention (agentskills.io), not
# any single agent's own path. Both OpenCode and Pi discover
# ~/.agents/skills/<name>/SKILL.md natively with zero additional config
# (see https://opencode.ai/docs/skills and pi-mono's skills.md docs).
#
# This module installs the full internal + superpowers skill set exactly
# once, regardless of which combination of opencode/claude/pi roles are
# enabled, closing the gap where each agent's home-manager module used to
# write its own duplicate copy under a per-agent path
# (.config/opencode/skills/<name>, .pi/agent/skills/<name>).
#
# Gated on "any skill-consuming role enabled" (skills.enabledRoles != []),
# not on any single agent's role.enable — the resolved skill set is shared
# across every agent that consumes it, so it doesn't belong inside
# opencode.nix, claude-code.nix, or pi-coding-agent.nix.
{
  osConfig,
  lib,
  ...
}: let
  skillsCfg = osConfig.myConfig.skills or {};
  hmLib = import ../lib.nix {inherit lib;};

  inherit
    (hmLib.mkFullSkillDirs {
      enabledRoles = skillsCfg.enabledRoles or [];
      superpowersPath = skillsCfg.superpowersPath or null;
    })
    skillDirs
    ;
in {
  config = lib.mkIf ((skillsCfg.enabledRoles or []) != []) {
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
