# myConfig.skills options — owned here, consumed by the home-manager skill
# installer and agent integrations. enabledRoles is set by modules/roles/default.nix.
{lib, ...}: {
  options.myConfig.skills = {
    enabledRoles = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "List of enabled roles for skill installation and optional metadata filtering (set automatically by bundle configuration)";
    };

    repository = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Pinned repository that contains the skills/<name>/SKILL.md directories";
    };
  };
}
