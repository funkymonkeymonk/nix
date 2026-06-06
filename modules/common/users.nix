{
  config,
  lib,
  options,
  ...
}:
with lib; let
  inherit (config.myConfig) isDarwin;
  # Check if home-manager module is available by checking if the option is defined
  homeManagerAvailable = builtins.hasAttr "home-manager" options;

  # Build home-manager user configs only if home-manager is available
  homeManagerUsersConfig = listToAttrs (map (user: {
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
            // lib.optionalAttrs (config.myConfig.onepassword.enable && isDarwin) {
              gpg = {
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
            ../../modules/home-manager/themes.nix
            ../../modules/home-manager/shell.nix
            ../../modules/home-manager/foundation.nix
          ]
          ++ optional config.myConfig.charm.enable ../../modules/home-manager/charm.nix
          ++ optional config.myConfig.opencode.enable ../../modules/home-manager/opencode.nix
          ++ optional config.myConfig.claude-code.enable ../../modules/home-manager/claude-code.nix
          ++ optional config.myConfig.pi.enable ../../modules/home-manager/pi-coding-agent.nix
          ++ optional (config.myConfig.vane.openaiBaseUrlOpnixItem != null) ../../modules/home-manager/vane-secrets.nix
          ++ optional config.myConfig.zellij.enable ../../modules/home-manager/zellij.nix
          ++ optional config.myConfig.agent-skills.enable ../../modules/home-manager/skills/install.nix
          ++ optional config.myConfig.higgs.enable ../../modules/home-manager/higgs.nix
          ++ optional config.myConfig.jj-autosync.enable ../../modules/home-manager/jj-autosync.nix
          ++ optional config.myConfig.email-agent.enable ../../modules/home-manager/email-agent.nix
          ++ optional config.myConfig.email-backup.enable ../../modules/home-manager/email-backup.nix
          ++ optional config.myConfig.fjj.enable ../../modules/home-manager/fjj.nix
          ++ optional config.myConfig.sketchybar.enable ../../modules/home-manager/sketchybar
          ++ optional (
            config.myConfig.roles.developer.enable
            || config.myConfig.roles.workstation.enable
          )
          ../../modules/home-manager/watch-ci-jobs.nix;

        # Pass user info and system config to home-manager modules
        _module.args = {
          userConfig = user;
          inherit (config) myConfig;
        };
      };
    })
    config.myConfig.users);
in {
  config =
    {
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
            // optionalAttrs (!isDarwin) {
              # NixOS-specific user options
              useDefaultShell = true;
            }
            // optionalAttrs user.isAdmin {
              # Additional admin configuration if needed
            };
        })
        config.myConfig.users);

      # Configure home-manager for each user (only if home-manager is available)
      # Using optionalAttrs to completely avoid defining home-manager when not available
    }
    // optionalAttrs homeManagerAvailable {
      home-manager.users = homeManagerUsersConfig;
    };
}
