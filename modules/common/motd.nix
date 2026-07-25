{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.myConfig.motd;

  motdScript = pkgs.writeShellApplication {
    name = "motd";
    runtimeInputs = [pkgs.chafa pkgs.curl];
    text = ''
      export MOTD_SHOW_HOSTNAME="${
        if cfg.showHostname
        then "1"
        else "0"
      }"
      export MOTD_SHOW_GIT_COMMIT="${
        if cfg.showGitCommit
        then "1"
        else "0"
      }"
      export MOTD_GITHUB_URL="${cfg.githubUrl}"
      export MOTD_EXTRA_MESSAGE="${cfg.extraMessage}"
      ${builtins.readFile ./motd.sh}
    '';
  };
in {
  options.myConfig.motd = {
    enable = mkOption {
      type = types.bool;
      default = true;
      description = "Enable MOTD (Message of the Day) showing git commit info on shell login";
    };

    showGitCommit = mkOption {
      type = types.bool;
      default = true;
      description = "Show the git commit hash the system was built from";
    };

    showHostname = mkOption {
      type = types.bool;
      default = true;
      description = "Show the system hostname";
    };

    showSystem = mkOption {
      type = types.bool;
      default = true;
      description = "Show the operating system and architecture";
    };

    extraMessage = mkOption {
      type = types.str;
      default = "";
      description = "Additional custom message to display in MOTD";
    };

    githubUrl = mkOption {
      type = types.str;
      default = "https://github.com/funkymonkeymonk/nix";
      description = "GitHub repository URL for linking to commits in MOTD";
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [motdScript];

    programs.zsh = {
      # IMPORTANT: motd must be the LAST thing invoked in interactiveShellInit
      # so that its screen-clear at the end wipes any prior output
      interactiveShellInit = ''
        if [ -z "''${INSIDE_EMACS}" ] && [ "''${TERM}" != "dumb" ] && [ -z "''${VSCODE_RESOLVING_ENVIRONMENT}" ]; then
          if command -v motd &>/dev/null; then
            motd 2>/dev/null
          fi
        fi
      '';
    };

    programs.bash = {
      # IMPORTANT: motd must be the LAST thing invoked in interactiveShellInit
      # so that its screen-clear at the end wipes any prior output
      interactiveShellInit = ''
        if [ -z "''${INSIDE_EMACS}" ] && [ "''${TERM}" != "dumb" ] && [ -z "''${VSCODE_RESOLVING_ENVIRONMENT}" ]; then
          if command -v motd &>/dev/null; then
            motd 2>/dev/null
          fi
        fi
      '';
    };
  };
}
