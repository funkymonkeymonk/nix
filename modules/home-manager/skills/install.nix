# Skills installation module
# Filters skills by enabled roles and installs them to ~/.config/opencode/skills/
# Also installs bundled commands to ~/.config/opencode/commands/
# Skills with autoLoad = true are concatenated into an instructions file for each agent
# External skills (source.type = "external") are installed via npx skills on activation
{
  osConfig,
  lib,
  pkgs,
  ...
}: let
  # Get skills config from OS config
  cfg = osConfig.myConfig.skills or {};
  manifest = import ./manifest.nix;

  # Get all enabled roles from config
  enabledRoles = cfg.enabledRoles or [];

  # Get superpowers path from flake input
  superpowersPath = cfg.superpowersPath or null;

  # Use default path if not specified (relative to home directory for home.file)
  skillsPath = cfg.skillsPath or ".config/opencode/skills";
  commandsPath = cfg.commandsPath or ".config/opencode/commands";

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

  # Filter auto-loaded skills (must be both enabled AND have autoLoad = true)
  autoLoadSkills =
    lib.filterAttrs (
      _name: skill: skill.autoLoad or false
    )
    allSkills;

  # Read and concatenate SKILL.md contents for auto-loaded skills
  autoLoadContent = lib.concatStringsSep "\n\n---\n\n" (lib.mapAttrsToList (
      name: skill: let
        skillMd =
          if skill.source.type == "internal"
          then let
            skillPath = skill.source.path + "/SKILL.md";
          in
            if builtins.pathExists skillPath
            then builtins.readFile skillPath
            else "# ${name}\n\n${skill.description}"
          else if skill.source.type == "superpowers" && superpowersPath != null
          then builtins.readFile "${superpowersPath}/skills/${skill.source.skillName}/SKILL.md"
          else "# ${name}\n\n${skill.description}";
      in
        skillMd
    )
    autoLoadSkills);

  hasAutoLoadSkills = autoLoadSkills != {};

  # Generate the auto-loaded skills instruction file
  autoLoadFile = lib.optionalAttrs hasAutoLoadSkills {
    "${skillsPath}/auto-loaded.md" = {
      text = autoLoadContent;
    };
  };

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

  # --- Generate home.file entries for each skill ---
  skillFiles =
    lib.mapAttrs' (
      name: skill: let
        skillDir = "${skillsPath}/${name}";
      in
        if skill.source.type == "internal"
        then
          # Internal: link the directory if it exists, fall back to placeholder
          let
            src = skill.source.path;
          in
            if builtins.pathExists src
            then
              lib.nameValuePair skillDir {
                source = src;
                recursive = true;
              }
            else
              lib.nameValuePair "${skillDir}/SKILL.md" {
                text = "# ${name}\n\n${skill.description}";
              }
        else if skill.source.type == "superpowers" && superpowersPath != null
        then
          # Superpowers: link from the flake input
          lib.nameValuePair skillDir {
            source = "${superpowersPath}/skills/${skill.source.skillName}";
            recursive = true;
          }
        else
          # External: write a placeholder noting the skill will be installed at activation
          # The real content is installed by the home.activation script via npx skills
          lib.nameValuePair "${skillDir}/SKILL.md" {
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
    allSkills;

  # Generate home.file entries for commands bundled with skills
  commandFiles = let
    # Get all skills that have commands defined
    skillsWithCommands = lib.filterAttrs (_name: skill: skill ? commands) allSkills;

    # Generate file entries for each command in each skill
    commandEntries = lib.concatLists (lib.mapAttrsToList (
        _skillName: skill:
          map (cmdName: {
            name = "${commandsPath}/${cmdName}.md";
            value = {
              source = "${skill.commands.path}/${cmdName}.md";
            };
          })
          skill.commands.list
      )
      skillsWithCommands);
  in
    lib.listToAttrs commandEntries;

  # Generate README with installed skills info
  readmeFile = {
    "${skillsPath}/README.md" = {
      text = ''
        # OpenCode Skills

        Skills installed based on enabled roles.

        ## Configuration

        Enabled roles: ${lib.concatStringsSep ", " enabledRoles}

        ## Installed Skills

        ${lib.concatStringsSep "\n" (lib.mapAttrsToList (
            name: skill: "- **${name}**: ${skill.description} (roles: ${lib.concatStringsSep ", " skill.roles})"
          )
          allSkills)}

        ## Installed Commands

        ${
          let
            skillsWithCommands = lib.filterAttrs (_name: skill: skill ? commands) allSkills;
            commandList = lib.concatLists (lib.mapAttrsToList (
                skillName: skill:
                  map (cmd: "- **/${cmd}** (from ${skillName})") skill.commands.list
              )
              skillsWithCommands);
          in
            if commandList == []
            then "_No commands installed_"
            else lib.concatStringsSep "\n" commandList
        }

        ## Adding Skills

        1. Add skill to `modules/home-manager/skills/manifest.nix`
        2. Assign to relevant role(s)
        3. Rebuild: `darwin-rebuild switch` or `nixos-rebuild switch`

        ## External Skills

        To import from external repos, add to manifest with:
        ```nix
        source = {
          type = "external";
          url = "github:owner/repo//path/to/skill.md";
        };
        ```
      '';
    };
  };
in {
  config = lib.mkIf (enabledRoles != []) {
    home.file = skillFiles // commandFiles // readmeFile // autoLoadFile;

    # Ensure nodejs is available for running npx skills (only when external skills present)
    home.packages = lib.mkIf hasExternalSkills [pkgs.nodejs];

    # Install external skills via npx skills on activation
    # This runs after home-manager writes all files (writeBoundary)
    # npx skills add is idempotent: re-running updates existing skills safely
    home.activation.installExternalSkills = lib.mkIf hasExternalSkills (
      lib.hm.dag.entryAfter ["writeBoundary"] ''
        echo "Installing external skills via npx skills..."
        ${externalActivationScript}
        echo "External skills installation complete."
      ''
    );
  };
}
