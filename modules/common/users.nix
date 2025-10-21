{ config, lib, ... }:
with lib;
{
  imports = [ ./options.nix ];

  config = {
    # Validation assertions
    assertions = [
      {
        assertion = lib.all (user: user.name != "") config.myConfig.users;
        message = "All users must have a non-empty name";
      }
      {
        assertion = lib.all (user: user.email != "") config.myConfig.users;
        message = "All users must have a non-empty email";
      }
    ];

    # Configure users based on myConfig.users
    # Note: Shell and home directories are handled by target-specific configurations
    users.users = listToAttrs (map (user: {
      name = user.name;
      value = {} // optionalAttrs user.isAdmin {
        # Additional admin configuration if needed
      };
    }) config.myConfig.users);

    # Configure home-manager for each user
    home-manager.users = listToAttrs (map (user: {
      name = user.name;
      value = {
        home = {
          username = user.name;
          homeDirectory = config.users.users.${user.name}.home or
                         (if builtins.elem config.nixpkgs.hostPlatform.system ["aarch64-darwin" "x86_64-darwin"]
                          then "/Users/${user.name}"
                          else "/home/${user.name}");
          stateVersion = "25.05";
        };

        programs.git = {
          enable = true;
          userName = user.name;
          userEmail = user.email;
          aliases = {
            co = "checkout";
            st = "status";
          };
          difftastic = {
            enable = true;
            background = "dark";
          };
          extraConfig = {
            pull.rebase = true;
            push.default = "current";
          };
        };

        # Include shared home-manager modules
        imports = [
          ../../modules/home-manager/shell.nix
        ] ++ optional config.myConfig.development.enable ../../modules/home-manager/development.nix
          ++ optional config.myConfig.media.enable ../../modules/home-manager/media.nix;
      };
    }) config.myConfig.users);
  };
}