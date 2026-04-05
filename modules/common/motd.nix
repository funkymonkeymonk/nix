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
