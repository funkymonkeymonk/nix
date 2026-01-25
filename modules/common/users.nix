{
  config,
  lib,
  pkgs,
  ...
}:
with lib; {
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
              if builtins.elem config.nixpkgs.hostPlatform.system ["aarch64-darwin" "x86_64-darwin"]
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
              if builtins.elem config.nixpkgs.hostPlatform.system ["aarch64-darwin" "x86_64-darwin"]
              then "/Users/${user.name}"
              else "/home/${user.name}"
            );
            stateVersion = "25.05";
          };

          programs.git =
            {
              userName = user.email;
              userEmail = user.email;
            }
            // lib.optionalAttrs config.myConfig.onepassword.enable {
              extraConfig = {
                gpg = lib.mkIf (lib.elem config.nixpkgs.hostPlatform.system ["aarch64-darwin" "x86_64-darwin"]) {
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
            includes = user.sshIncludes;
            extraConfig =
              lib.optionalString (
                config.myConfig.onepassword.enableSSHAgent
                && lib.elem config.nixpkgs.hostPlatform.system ["aarch64-darwin" "x86_64-darwin"]
              ) ''
                Host *
                  IdentityAgent "~/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"
              '';
          };

          # Managed SSH config file for macOS 1Password agent
          home.file.".ssh/config" =
            lib.mkIf (
              config.myConfig.onepassword.enableSSHAgent
              && lib.elem config.nixpkgs.hostPlatform.system ["aarch64-darwin" "x86_64-darwin"]
            ) {
              text = ''
                Host *
                  IdentityAgent "~/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"
              '';
            };

          # Allowed signers file for SSH signature verification
          home.file.".ssh/allowed_signers".text =
            lib.mkIf (
              config.myConfig.onepassword.enableGitSigning
              && config.myConfig.onepassword.enable
              && lib.elem config.nixpkgs.hostPlatform.system ["aarch64-darwin" "x86_64-darwin"]
            ) ''
              ${user.email} ${config.myConfig.onepassword.signingKey}
            '';

          # Include shared home-manager modules
          imports =
            [
              ../../modules/home-manager/shell.nix
            ]
            ++ optional config.myConfig.development.enable ../../modules/home-manager/development.nix
            ++ optional config.myConfig.media.enable ../../modules/home-manager/media.nix;
        };
      })
      config.myConfig.users);
  };
}
