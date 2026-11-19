{
  config,
  lib,
  options,
  pkgs,
  ...
}:
with lib; let
  inherit (config.myConfig) isDarwin;
  homeManagerAvailable = builtins.hasAttr "home-manager" options;
  sshAgentEnabled = config.myConfig.onepassword.enable && config.myConfig.onepassword.enableSSHAgent;
  githubSshEnabled = sshAgentEnabled && config.myConfig.onepassword.useSSHForGitHub;
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
            }
            // lib.optionalAttrs githubSshEnabled {
              url."git@github.com:".insteadOf = ["https://github.com/"];
            };
        };

        programs.gh = {
          enable = true;
          settings.git_protocol =
            if githubSshEnabled
            then "ssh"
            else "https";
        };

        xdg.configFile."gh/config.yml".force = true;

        programs.ssh = {
          enable = true;
          enableDefaultConfig = false;
          includes = user.sshIncludes;
          settings = lib.optionalAttrs sshAgentEnabled {
            "*" = {IdentityAgent = sshIdentityAgent;};
          };
        };

        home.sessionVariables = lib.optionalAttrs sshAgentEnabled {
          SSH_AUTH_SOCK = sshAgentSocket;
        };

        manual.manpages.enable = lib.mkDefault false;

        home.file.".ssh/allowed_signers".text =
          lib.optionalString (
            config.myConfig.onepassword.enableGitSigning
            && config.myConfig.onepassword.enable
          ) ''
            ${user.email} ${config.myConfig.onepassword.signingKey}
          '';

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
          ++ optional config.myConfig.email-agent.enable ../../modules/home-manager/email-agent.nix
          ++ optional config.myConfig.email-backup.enable ../../modules/home-manager/email-backup.nix;

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
              useDefaultShell = true;
            };
        })
        config.myConfig.users);
    }
    // optionalAttrs homeManagerAvailable {
      home-manager.users = homeManagerUsersConfig;
    };
}
