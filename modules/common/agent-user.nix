# Agent user type - service account without sudo access
# For running AI agents and automation services
{
  config,
  lib,
  ...
}: {
  options.myConfig.agentUser = {
    enable = lib.mkEnableOption "agent user account for service automation";

    name = lib.mkOption {
      type = lib.types.str;
      default = "agent";
      description = "Username for the agent account";
    };

    home = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/agent";
      description = "Home directory for the agent user";
    };

    uid = lib.mkOption {
      type = lib.types.nullOr lib.types.int;
      default = null;
      description = "Fixed UID for the agent user (auto-assigned if null)";
    };

    gid = lib.mkOption {
      type = lib.types.nullOr lib.types.int;
      default = null;
      description = "Fixed GID for the agent group (auto-assigned if null)";
    };
  };

  config = let
    cfg = config.myConfig.agentUser;
  in
    lib.mkIf cfg.enable {
      users.groups.${cfg.name} = lib.mkIf (cfg.gid != null) {
        inherit (cfg) gid;
      };

      users.users.${cfg.name} = {
        isSystemUser = true;
        home = lib.mkDefault cfg.home;
        createHome = true;
        group = cfg.name;
        uid = lib.mkIf (cfg.uid != null) cfg.uid;
        description = "Service automation agent account (no sudo access)";
        extraGroups = lib.mkForce [];
      };
    };
}
