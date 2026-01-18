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
          # Propagate specific myConfig options to user configurations
          myConfig = {
            inherit (config.myConfig) agent-skills;
          };

          home = {
            username = user.name;
            homeDirectory = lib.mkDefault (
              if builtins.elem config.nixpkgs.hostPlatform.system ["aarch64-darwin" "x86_64-darwin"]
              then "/Users/${user.name}"
              else "/home/${user.name}"
            );
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
            extraConfig =
              {
                init.defaultBranch = "main";
                pull.rebase = true;
                push.default = "current";
              }
              // lib.optionalAttrs (builtins.elem config.nixpkgs.hostPlatform.system ["aarch64-darwin" "x86_64-darwin"]) {
                gpg = {
                  format = "ssh";
                  ssh = {
                    program = "/Applications/1Password.app/Contents/MacOS/op-ssh-sign";
                    allowedSignersFile = "~/.ssh/allowed_signers";
                  };
                };
                commit.gpgsign = true;
                user.signingkey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIIxGvpCUmx1UV3K22/+sWLdRknZmlTmQgckoAUCApF8";
              };
          };

          programs.ssh = {
            enable = true;

            extraConfig = lib.optionalString (builtins.elem config.nixpkgs.hostPlatform.system ["aarch64-darwin" "x86_64-darwin"]) ''
              Host *
                IdentityAgent "~/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"
            '';

            includes = user.sshIncludes;
          };

          # Ensure a managed per-user SSH config is created on macOS so the 1Password
          # IdentityAgent socket is available to the SSH client. This writes ~/.ssh/config.
          home.file.".ssh/config".text = lib.optionalString (builtins.elem config.nixpkgs.hostPlatform.system ["aarch64-darwin" "x86_64-darwin"]) ''
            Host *
              IdentityAgent "~/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"
          '';

          # Allowed signers file for SSH signature verification
          # Maps email addresses to trusted SSH public keys for local commit verification
          home.file.".ssh/allowed_signers".text = lib.optionalString (builtins.elem config.nixpkgs.hostPlatform.system ["aarch64-darwin" "x86_64-darwin"]) ''
            ${user.email} ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIIxGvpCUmx1UV3K22/+sWLdRknZmlTmQgckoAUCApF8
          '';

          # Include shared home-manager modules
          imports =
            [
              ../../modules/home-manager/shell.nix
              ../../modules/home-manager/agent-skills
            ]
            ++ optional config.myConfig.development.enable ../../modules/home-manager/development.nix
            ++ optional config.myConfig.media.enable ../../modules/home-manager/media.nix;
        };
      })
      config.myConfig.users);
  };
}
