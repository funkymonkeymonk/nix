{
  config,
  lib,
  options,
  pkgs,
  ...
}:
with lib; let
  inherit (config.myConfig) isDarwin;
  # Check if home-manager module is available by checking if the option is defined
  homeManagerAvailable = builtins.hasAttr "home-manager" options;

  # Build home-manager user configs only if home-manager is available
  sshAgentEnabled = config.myConfig.onepassword.enable && config.myConfig.onepassword.enableSSHAgent;
  sshSigningProgram =
    if isDarwin
    then "/Applications/1Password.app/Contents/MacOS/op-ssh-sign"
    else "${pkgs._1password-cli}/bin/op-ssh-sign";
  homeManagerUsersConfig = listToAttrs (map (user: let
      homeDirectory =
        if isDarwin
        then "/Users/${user.name}"
        else "/home/${user.name}";
      sshAgentSocket =
        if isDarwin
        then "${homeDirectory}/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"
        else "${homeDirectory}/.1password/agent.sock";
      sshIdentityAgent =
        if isDarwin
        then "\"~/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock\""
        else sshAgentSocket;
    in {
      inherit (user) name;
      value = {
        home = {
          username = user.name;
          homeDirectory = lib.mkDefault homeDirectory;
          stateVersion = "25.05";
        };

        programs.git = {
          enable = true;
          settings =
            {
              user = {
                inherit (user) name email;
              };
            }
            // lib.optionalAttrs config.myConfig.onepassword.enable {
              gpg = {
                format = "ssh";
                ssh = {
                  program = sshSigningProgram;
                  allowedSignersFile = "~/.ssh/allowed_signers";
                };
              };
              commit.gpgsign = config.myConfig.onepassword.enableGitSigning;
              user.signingkey = config.myConfig.onepassword.signingKey;
              url."git@github.com:".insteadOf = ["https://github.com/"];
            };
        };

        programs.gh = {
          enable = true;
          settings.git_protocol = "ssh";
        };

        xdg.configFile."gh/config.yml".force = true;

        programs.ssh = {
          enable = true;
          enableDefaultConfig = false;
          includes = user.sshIncludes;
          settings = lib.optionalAttrs sshAgentEnabled {
            "*" = {
              IdentityAgent = sshIdentityAgent;
            };
          };
        };

        home.sessionVariables = lib.optionalAttrs sshAgentEnabled {
          SSH_AUTH_SOCK = sshAgentSocket;
        };

        # Disable home-manager manpages to avoid expensive options.json
        # generation and builtins.derivation context warnings
        manual.manpages.enable = lib.mkDefault false;

        # Allowed signers file for SSH signature verification
        # Maps email addresses to trusted SSH public keys for local commit verification
        home.file.".ssh/allowed_signers".text =
          lib.optionalString (
            config.myConfig.onepassword.enableGitSigning
            && config.myConfig.onepassword.enable
          ) ''
            ${user.email} ${config.myConfig.onepassword.signingKey}
          '';

        # Include shared home-manager modules
        imports =
          [
            ../../modules/home-manager/themes.nix
            ../../modules/home-manager/shell.nix
            ../../modules/home-manager/foundation.nix
            ../../modules/home-manager/skills/canonical-install.nix
          ]
          ++ optional config.myConfig.charm.enable ../../modules/home-manager/charm.nix
          ++ optional config.myConfig.opencode.enable ../../modules/home-manager/opencode.nix
          ++ optional config.myConfig.claude-code.enable ../../modules/home-manager/claude-code.nix
          ++ optional config.myConfig.pi.enable ../../modules/home-manager/pi-coding-agent.nix
          ++ optional config.myConfig.zellij.enable ../../modules/home-manager/zellij.nix
          ++ optional config.myConfig.obsidian.enable ../../modules/home-manager/obsidian.nix
          ++ optional config.myConfig.agent-skills.enable ../../modules/home-manager/skills/install.nix
          ++ optional config.myConfig.email-agent.enable ../../modules/home-manager/email-agent.nix
          ++ optional config.myConfig.email-backup.enable ../../modules/home-manager/email-backup.nix;

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
