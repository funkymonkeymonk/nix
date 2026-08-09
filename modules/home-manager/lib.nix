# Shared helper functions for home-manager modules
{lib}:
with lib; rec {
  # Convert kebab-case to camelCase
  # Example: "my-api-key" -> "myApiKey"
  toCamelCase = str:
    lib.concatStrings (
      lib.imap0 (
        i: s:
          if i == 0
          then s
          else lib.toUpper (lib.substring 0 1 s) + lib.substring 1 (-1) s
      ) (lib.splitString "-" str)
    );

  # Build an opnix secret reference using the default vault.
  # If ref already starts with 'op://', it's used as-is (explicit override).
  # Otherwise, the default vault is prepended.
  mkOpnixRef = defaultVault: ref:
    if lib.hasPrefix "op://" ref
    then ref
    else "op://${defaultVault}/${ref}";

  # Build opnix secrets configuration from a prefix and items
  # prefix: string prefix for secret names (e.g., "opencode", "claudeCode")
  # defaultVault: default 1Password vault name
  # items: attrset of name -> { onePasswordItem, secretPath }
  mkOpnixSecrets = prefix: defaultVault: items:
    lib.mapAttrs' (name: item:
      lib.nameValuePair "${prefix}${toCamelCase name}ApiKey" {
        reference = mkOpnixRef defaultVault item.onePasswordItem;
        path = item.secretPath;
        mode = "0600";
      })
    (lib.filterAttrs (_: item: item.onePasswordItem != "") items);

  # Build opnix secrets configuration for arbitrary secrets (not just API keys)
  # prefix: string prefix for secret names (e.g., "opencode")
  # defaultVault: default 1Password vault name
  # items: attrset of secretName -> { reference, path, mode? }
  mkOpnixSecretsGeneric = prefix: defaultVault: items:
    lib.mapAttrs' (name: item:
      lib.nameValuePair "${prefix}${toCamelCase name}" {
        reference = mkOpnixRef defaultVault item.reference;
        inherit (item) path;
        mode = item.mode or "0600";
      })
    (lib.filterAttrs (_: item: item.reference != "") items);

  # Build auto-loaded skills content from the shared skill manifest.
  #
  # Filters modules/home-manager/skills/manifest.nix down to skills whose
  # `roles` intersect `enabledRoles`, then further to skills tagged
  # `autoLoad = true`, resolving each one's SKILL.md content (internal or
  # superpowers source), and concatenating them with `---` separators.
  #
  # enabledRoles: list of role names, e.g. config.myConfig.skills.enabledRoles
  # superpowersPath: path to the superpowers skills repo, or null if unset
  #
  # Returns { autoLoadSkills, autoLoadContent, hasAutoLoadSkills }.
  mkAutoLoadSkills = {
    enabledRoles,
    superpowersPath ? null,
    pkgs ? null,
    inputs ? null,
  }: let
    manifest = import ./skills/manifest.nix {inherit pkgs inputs;};
    enabledSkills =
      lib.filterAttrs (
        _name: skill:
          lib.any (role: lib.elem role skill.roles) enabledRoles
      )
      manifest;
    autoLoadSkills =
      lib.filterAttrs (
        _name: skill: skill.autoLoad or false
      )
      enabledSkills;
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
  in {
    inherit autoLoadSkills autoLoadContent hasAutoLoadSkills;
  };

  # Build the full set of internal + superpowers skill directories for a
  # given set of enabled roles, in the shape expected by home-manager's
  # native programs.opencode.skills / programs.claude-code.skills options
  # (an attrset of skill-name -> directory path).
  #
  # External skills (source.type == "external") are deliberately excluded:
  # they are installed at activation time via `npx skills add`
  # (see modules/home-manager/skills/install.nix), which is a runtime
  # network fetch and cannot be expressed as a static Nix value.
  #
  # Dependencies (skill.deps) are resolved and included even if their own
  # roles aren't in enabledRoles, matching install.nix's existing behavior.
  #
  # enabledRoles: list of role names, e.g. config.myConfig.skills.enabledRoles
  # superpowersPath: path to the superpowers skills repo, or null if unset
  #
  # Returns { skillDirs, allSkills } where skillDirs is ready to assign
  # directly to programs.<agent>.skills, and allSkills is the resolved
  # manifest subset (useful for building commands / README content).
  mkFullSkillDirs = {
    enabledRoles,
    superpowersPath ? null,
    pkgs ? null,
    inputs ? null,
  }: let
    manifest = import ./skills/manifest.nix {inherit pkgs inputs;};
    enabledSkills =
      lib.filterAttrs (
        _name: skill:
          lib.any (role: lib.elem role skill.roles) enabledRoles
      )
      manifest;
    # Resolve deps (include deps even if their roles aren't enabled)
    allSkillNames = lib.concatLists (lib.mapAttrsToList (
        name: skill:
          [name] ++ skill.deps
      )
      enabledSkills);
    allSkills = lib.listToAttrs (map (name: {
      inherit name;
      value = manifest.${name};
    }) (lib.unique allSkillNames));
    # Only internal + superpowers skills can be expressed as static paths.
    installableSkills =
      lib.filterAttrs (
        _name: skill:
          skill.source.type
          == "internal"
          || (skill.source.type == "superpowers" && superpowersPath != null)
      )
      allSkills;
    skillDirs =
      lib.mapAttrs (
        _name: skill:
          if skill.source.type == "internal"
          then skill.source.path
          else "${superpowersPath}/skills/${skill.source.skillName}"
      )
      installableSkills;
  in {
    inherit skillDirs allSkills;
  };

  # Build a flat attrset of command-name -> file path from a resolved set of
  # manifest skills (as returned by mkFullSkillDirs's `allSkills`), in the
  # shape expected by home-manager's native programs.opencode.commands
  # option (attrsOf (either lines path)).
  #
  # allSkills: attrset of skill-name -> manifest entry, e.g.
  #            (mkFullSkillDirs { ... }).allSkills
  mkSkillCommands = allSkills: let
    skillsWithCommands = lib.filterAttrs (_name: skill: skill ? commands) allSkills;
  in
    lib.foldl' (
      acc: skill:
        acc
        // lib.listToAttrs (map (cmdName: {
            name = cmdName;
            value = "${skill.commands.path}/${cmdName}.md";
          })
          skill.commands.list)
    ) {} (lib.attrValues skillsWithCommands);
}
