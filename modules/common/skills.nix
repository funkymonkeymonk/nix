# myConfig.skills options — owned here, consumed by modules/home-manager/skills/*,
# modules/home-manager/opencode.nix, modules/home-manager/claude-code.nix,
# and modules/home-manager/pi-coding-agent.nix. enabledRoles is set by
# modules/roles/default.nix from the enabled myConfig.roles.
{lib, ...}: {
  options.myConfig.skills = {
    enabledRoles = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "List of enabled roles for skills filtering (set automatically by bundle configuration)";
    };

    skillsPath = lib.mkOption {
      type = lib.types.str;
      default = ".config/opencode/skills";
      description = "Path relative to home directory where skills are installed";
    };

    superpowersPath = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Path to the superpowers flake input (set automatically from flake inputs)";
    };

    externalInputs = lib.mkOption {
      type = lib.types.attrsOf lib.types.path;
      default = {};
      description = "Attribute set of external skill repository flake inputs (e.g., vercel-skills = inputs.vercel-skills)";
    };
  };
}
