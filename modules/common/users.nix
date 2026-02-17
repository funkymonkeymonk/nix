{
  config,
  lib,
  ...
}:
with lib; let
  inherit (config.myConfig) isDarwin;
in {
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
    # Note: Shell is handled by target-specific configurations
    users.users = listToAttrs (map (user: {
        inherit (user) name;
        value =
          {
            home =
              if isDarwin
              then "/Users/${user.name}"
              else "/home/${user.name}";
          }
          // optionalAttrs user.isAdmin {
            # Additional admin configuration if needed
          };
      })
      config.myConfig.users);

    # Configure home-manager for each user
    home-manager.users = listToAttrs (map (user: {
        inherit (user) name;
        value = {
          home = {
            username = user.name;
            homeDirectory = lib.mkDefault (
              if isDarwin
              then "/Users/${user.name}"
              else "/home/${user.name}"
            );
            stateVersion = "25.05";
          };

          programs.git = {
            settings =
              {
                user = {
                  inherit (user) name email;
                };
              }
              // lib.optionalAttrs config.myConfig.onepassword.enable {
                gpg = lib.mkIf isDarwin {
                  format = "ssh";
                  ssh = {
                    program = "/Applications/1Password.app/Contents/MacOS/op-ssh-sign";
                    allowedSignersFile = "~/.ssh/allowed_signers";
                  };
                };
                commit.gpgsign = config.myConfig.onepassword.enableGitSigning;
                user.signingkey = config.myConfig.onepassword.signingKey;
              };
          };

          programs.ssh = {
            enable = true;
            enableDefaultConfig = false;
            includes = user.sshIncludes;
            matchBlocks = lib.optionalAttrs (config.myConfig.onepassword.enableSSHAgent && isDarwin) {
              "*" = {
                extraOptions = {
                  IdentityAgent = "\"~/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock\"";
                };
              };
            };
          };

          # Allowed signers file for SSH signature verification
          # Maps email addresses to trusted SSH public keys for local commit verification
          home.file.".ssh/allowed_signers".text =
            lib.optionalString (
              config.myConfig.onepassword.enableGitSigning
              && config.myConfig.onepassword.enable
              && isDarwin
            ) ''
              ${user.email} ${config.myConfig.onepassword.signingKey}
            '';

          # Include shared home-manager modules
          imports =
            [
              ../../modules/home-manager/shell.nix
            ]
            ++ optional config.myConfig.development.enable ../../modules/home-manager/development.nix
            ++ optional config.myConfig.opencode.enable ../../modules/home-manager/opencode.nix
            ++ optional config.myConfig.zellij.enable ../../modules/home-manager/zellij.nix
            ++ optional ((config.myConfig.skills.enabledRoles or []) != []) ../../modules/home-manager/skills/install.nix;
        };
      })
      config.myConfig.users);
  };
}
