{lib, ...}:
with lib; {
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
          sshIncludes = mkOption {
            type = types.listOf types.str;
            default = [];
            description = "Additional SSH config files to include";
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

    secrets = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Enable secret management with 1Password";
      };
    };

    syncthing = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Enable Syncthing file synchronization service";
      };

      gui = {
        enable = mkOption {
          type = types.bool;
          default = true;
          description = "Enable Syncthing web GUI";
        };
        port = mkOption {
          type = types.port;
          default = 8384;
          description = "Port for Syncthing web GUI";
        };
        address = mkOption {
          type = types.str;
          default = "127.0.0.1";
          description = "Address to bind GUI to (127.0.0.1 for localhost only)";
        };
        user = mkOption {
          type = types.str;
          default = "";
          description = "GUI username (empty for no auth)";
        };
        password = mkOption {
          type = types.str;
          default = "";
          description = "GUI password (empty for no auth)";
        };
      };

      folders = mkOption {
        type = types.attrsOf (types.submodule {
          options = {
            path = mkOption {
              type = types.str;
              description = "Local path to sync";
            };
            id = mkOption {
              type = types.str;
              description = "Unique folder ID";
            };
            label = mkOption {
              type = types.str;
              default = "";
              description = "Human-readable folder label";
            };
            devices = mkOption {
              type = types.listOf types.str;
              default = [];
              description = "List of device IDs to sync with";
            };
            ignorePerms = mkOption {
              type = types.bool;
              default = true;
              description = "Ignore permission changes when syncing";
            };
            versioning = {
              type = mkOption {
                type = types.enum ["none" "simple" "staggered" "trashcan"];
                default = "simple";
                description = "Versioning strategy";
              };
              params = mkOption {
                type = types.attrs;
                default = {};
                description = "Versioning parameters";
              };
            };
          };
        });
        default = {};
        description = "Syncthing folder configurations";
      };

      devices = mkOption {
        type = types.attrsOf (types.submodule {
          options = {
            id = mkOption {
              type = types.str;
              description = "Device ID";
            };
            name = mkOption {
              type = types.str;
              description = "Device name";
            };
            addresses = mkOption {
              type = types.listOf types.str;
              default = [];
              description = "Device addresses for direct connection";
            };
            compression = mkOption {
              type = types.enum ["always" "never" "metadata"];
              default = "metadata";
              description = "Compression level";
            };
            introducer = mkOption {
              type = types.bool;
              default = false;
              description = "Allow this device to introduce other devices";
            };
          };
        });
        default = {};
        description = "Syncthing device configurations";
      };

      extraOptions = mkOption {
        type = types.attrs;
        default = {};
        description = "Additional Syncthing configuration options";
      };
    };
  };
}
