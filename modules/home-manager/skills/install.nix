# External skills activation module
#
# Historically this module also installed internal + superpowers skills
# as home.file entries for opencode. That responsibility has moved to each
# agent's own home-manager module (opencode.nix, claude-code.nix,
# pi-coding-agent.nix), which now uses home-manager's native
# programs.<agent>.skills option (or, for pi, its own home.file wiring) via
# the shared modules/home-manager/lib.nix#mkFullSkillDirs helper. Leaving
# that logic here too would write the exact same target paths twice and
# trip home-manager's "Conflicting managed target files" assertion.
#
# What's left here is genuinely irreplaceable: skills with
# source.type = "external" are fetched over the network AT ACTIVATION TIME
# via `npx skills add`, which cannot be expressed as a static Nix value.
# This module still owns that mechanism, writing placeholder SKILL.md files
# (replaced by the real content when the activation script runs) and the
# activation script itself.
{
  osConfig,
  lib,
  pkgs,
  inputs ? null,
  ...
}: let
  # Get skills config from OS config
  cfg = osConfig.myConfig.skills or {};
  manifest = import ./manifest.nix {inherit pkgs inputs;};

  # Get all enabled roles from config
  enabledRoles = cfg.enabledRoles or [];

  # Use default path if not specified (relative to home directory for home.file)
  skillsPath = cfg.skillsPath or ".config/opencode/skills";

  # Filter skills that match any enabled role
  skillsForRoles = roles:
    lib.filterAttrs (
      _name: skill:
        lib.any (role: lib.elem role skill.roles) roles
    )
    manifest;

  # Get skills for current roles
  enabledSkills = skillsForRoles enabledRoles;

  # Resolve dependencies (include deps even if their roles aren't enabled)
  allSkillNames = lib.concatLists (lib.mapAttrsToList (
      name: skill:
        [name] ++ skill.deps
    )
    enabledSkills);

  # Get unique skills including dependencies
  allSkills = lib.listToAttrs (map (name: {
    inherit name;
    value = manifest.${name};
  }) (lib.unique allSkillNames));

  # --- External skill activation via npx skills ---

  # Filter external skills from enabled skills
  externalSkills =
    lib.filterAttrs (
      _name: skill: skill.source.type or "" == "external"
    )
    allSkills;

  hasExternalSkills = externalSkills != {};

  # Map manifest roles to npx skills --agent flags
  # OpenCode agent: opencode, Claude Code agent: claude-code, Pi agent: pi
  roleToAgents = {
    opencode = ["opencode"];
    claude = ["claude-code"];
    pi = ["pi"];
    developer = ["opencode" "claude-code" "pi"];
    workstation = ["opencode" "claude-code"];
  };

  # Collect unique agent flags for a skill based on its roles
  agentFlagsForSkill = skill:
    lib.unique (lib.concatLists (
      map (role: roleToAgents.${role} or []) skill.roles
    ));

  # Generate the npx skills add command for one external skill
  # Uses --global so skills install to ~/.<agent>/skills/ (not project-local)
  # Uses --yes for non-interactive (CI-friendly) installation
  externalSkillCommand = _name: skill: let
    url = skill.source.url or "";
    agents = agentFlagsForSkill skill;
    agentFlags = lib.concatMapStringsSep " " (a: "--agent ${a}") agents;
  in
    lib.optionalString (url != "") "npx --yes skills@latest add ${url} --global --yes ${agentFlags}";

  # Generate all external skill install commands (filter out empty strings)
  externalInstallCommands =
    lib.filter (cmd: cmd != "")
    (lib.mapAttrsToList externalSkillCommand externalSkills);

  # Build the activation script body
  externalActivationScript = lib.concatStringsSep "\n" externalInstallCommands;

  # Placeholder files for external skills only. The real content is
  # installed by the home.activation script via npx skills; this note
  # exists so `.../skills/<name>/SKILL.md` is discoverable before the
  # first activation runs.
  externalSkillFiles =
    lib.mapAttrs' (
      name: skill:
        lib.nameValuePair "${skillsPath}/${name}/SKILL.md" {
          force = true;
          text = ''
            # ${name}

            ${skill.description}

            ## Source

            External skill from: ${skill.source.url or "unknown"}

            **Note**: This skill is installed at system activation via `npx skills`.
            The placeholder will be replaced when the activation script runs.
          '';
        }
    )
    externalSkills;
in {
  config = lib.mkIf hasExternalSkills {
    home.file = externalSkillFiles;

    # Ensure nodejs is available for running npx skills
    home.packages = [pkgs.nodejs];

    # Install external skills via npx skills on activation
    # This runs after home-manager writes all files (writeBoundary)
    # npx skills add is idempotent: re-running updates existing skills safely
    home.activation.installExternalSkills = lib.hm.dag.entryAfter ["writeBoundary"] ''
      echo "Installing external skills via npx skills..."
      ${externalActivationScript}
      echo "External skills installation complete."
    '';
  };
}
