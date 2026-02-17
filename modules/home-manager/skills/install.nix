# Skills installation module
# Filters skills by enabled roles and installs them to ~/.config/opencode/skills/
{
  config,
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

  # Use default path if not specified
  skillsPath = cfg.skillsPath or "~/.config/opencode/skills";

  # Filter skills that match any enabled role
  skillsForRoles = roles:
    lib.filterAttrs (
      name: skill:
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

  # Generate home.file entries for each skill
  skillFiles =
    lib.mapAttrs' (
      name: skill: let
        skillDir = "${skillsPath}/${name}";
      in
        if skill.source.type == "internal"
        then
          # Internal: link the directory
          lib.nameValuePair skillDir {
            source = skill.source.path;
            recursive = true;
          }
        else
          # External: fetch and link (simplified - just reference for now)
          lib.nameValuePair "${skillDir}/SKILL.md" {
            text = ''
              # ${name}

              ${skill.description}

              ## Source

              External skill from: ${skill.source.url}

              **Note**: External skill fetching not yet implemented.
              To add this skill, copy the content from the URL above.
            '';
          }
    )
    allSkills;

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
    home.file = skillFiles // readmeFile;
  };
}
