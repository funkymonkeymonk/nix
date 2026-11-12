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
  mkOpnixSecrets = prefix: defaultVault: isDarwin: items:
    lib.mapAttrs' (name: item:
      lib.nameValuePair "${prefix}${toCamelCase name}ApiKey" {
        reference = mkOpnixRef defaultVault item.onePasswordItem;
        path = item.secretPath;
        group =
          if isDarwin
          then "staff"
          else "users";
        mode = "0600";
      })
    (lib.filterAttrs (_: item: item.onePasswordItem != "") items);

  # Build opnix secrets configuration for arbitrary secrets (not just API keys)
  # prefix: string prefix for secret names (e.g., "opencode")
  # defaultVault: default 1Password vault name
  # items: attrset of secretName -> { reference, path, mode? }
  mkOpnixSecretsGeneric = prefix: defaultVault: isDarwin: items:
    lib.mapAttrs' (name: item:
      lib.nameValuePair "${prefix}${toCamelCase name}" {
        reference = mkOpnixRef defaultVault item.reference;
        inherit (item) path;
        group =
          if isDarwin
          then "staff"
          else "users";
        mode = item.mode or "0600";
      })
    (lib.filterAttrs (_: item: item.reference != "") items);

  # Find every valid skill directory in the pinned personal skills input.
  # A directory is a skill only when it contains its required SKILL.md file.
  mkRepoSkillDirs = {skillsRepo ? null}: let
    skillsRoot =
      if skillsRepo == null
      then null
      else skillsRepo + "/skills";
    entries =
      if skillsRoot == null
      then {}
      else builtins.readDir skillsRoot;
    validEntries =
      lib.filterAttrs (
        name: kind:
          kind
          == "directory"
          && builtins.pathExists (skillsRoot + "/${name}/SKILL.md")
      )
      entries;
  in
    lib.mapAttrs (name: _kind: skillsRoot + "/${name}") validEntries;

  # Build auto-loaded content for metadata entries that still exist in the
  # repository. Skill content always comes from the pinned repository input.
  mkAutoLoadSkills = {
    enabledRoles,
    skillsRepo ? null,
  }: let
    manifest = import ./skills/manifest.nix;
    skillDirs = mkRepoSkillDirs {inherit skillsRepo;};
    enabledSkills =
      lib.filterAttrs (
        name: skill:
          builtins.hasAttr name skillDirs
          && lib.any (role: lib.elem role skill.roles) enabledRoles
      )
      manifest;
    autoLoadSkills =
      lib.filterAttrs (
        _name: skill: skill.autoLoad or false
      )
      enabledSkills;
    autoLoadContent = lib.concatStringsSep "\n\n---\n\n" (lib.mapAttrsToList (
        name: _skill: builtins.readFile (skillDirs.${name} + "/SKILL.md")
      )
      autoLoadSkills);
    hasAutoLoadSkills = autoLoadSkills != {};
  in {
    inherit autoLoadSkills autoLoadContent hasAutoLoadSkills;
  };

  # Return all skills from the pinned repository for installation by
  # home-manager. `allSkills` retains optional role metadata for agent
  # commands and auto-loaded instructions.
  mkFullSkillDirs = {
    enabledRoles,
    skillsRepo ? null,
  }: let
    manifest = import ./skills/manifest.nix;
    skillDirs = mkRepoSkillDirs {inherit skillsRepo;};
    enabledMetadata =
      lib.filterAttrs (
        name: skill:
          builtins.hasAttr name skillDirs
          && lib.any (role: lib.elem role skill.roles) enabledRoles
      )
      manifest;
    allSkillNames = lib.concatLists (lib.mapAttrsToList (
        name: skill:
          [name] ++ (skill.deps or [])
      )
      enabledMetadata);
    allSkills = lib.listToAttrs (map (name: {
      inherit name;
      value = manifest.${name};
    }) (lib.unique (lib.filter (name: builtins.hasAttr name skillDirs) allSkillNames)));
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
