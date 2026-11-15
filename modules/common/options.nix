{
  lib,
  pkgs,
  ...
}:
with lib; {
  options.myConfig = {
    collector.destinationHostname = mkOption {
      type = types.str;
      default = "localhost";
      description = "Hostname used by log collectors when sending data to the central Loki service.";
    };

    # Computed helper for platform detection (read-only)
    # Uses _module.args.pkgs which is always available during module evaluation
    isDarwin = mkOption {
      type = types.bool;
      default = builtins.elem pkgs.stdenv.hostPlatform.system ["aarch64-darwin" "x86_64-darwin"];
      readOnly = true;
      description = "Whether the current system is Darwin (macOS)";
    };

    ssh.enable = mkOption {
      type = types.bool;
      default = false;
      description = "Enable SSH access for this machine. Darwin hosts are disabled unless they opt in.";
    };

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
            default = true;
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

    # Role toggles — each is now owned by its own module in modules/roles/
    roles = {};
  };
}
