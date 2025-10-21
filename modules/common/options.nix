{ lib, ... }:
with lib;
{
  options.myConfig = {
    users = mkOption {
      type = types.listOf (types.submodule {
        options = {
          name = mkOption {
            type = types.str;
            description = "Username for the user account";
          };
          email = mkOption {
            type = types.str;
            description = "Email address for the user";
          };
          fullName = mkOption {
            type = types.str;
            default = "";
            description = "Full name of the user";
          };
          isAdmin = mkOption {
            type = types.bool;
            default = false;
            description = "Whether the user should have admin privileges";
          };
        };
      });
      default = [];
      description = "List of users to configure on the system";
    };

    system = {
      enableSecurity = mkOption {
        type = types.bool;
        default = true;
        description = "Enable basic security hardening";
      };

      enableUpdates = mkOption {
        type = types.bool;
        default = true;
        description = "Enable automatic system updates";
      };
    };

    development = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Enable development tools and environment";
      };

      languages = mkOption {
        type = types.listOf types.str;
        default = [];
        description = "Programming languages to support";
      };
    };

    media = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Enable media applications and tools";
      };
    };
  };


}