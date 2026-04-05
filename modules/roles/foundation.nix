{
  config,
  options,
  lib,
  pkgs,
  ...
}: let
  cfg = config.myConfig.roles.foundation;
  inherit (config.myConfig) isDarwin;
  hasHomebrew = options ? homebrew;
in {
  config = lib.mkIf cfg.enable (
    lib.mkMerge ([
        {
          environment.systemPackages = with pkgs; [
            # Editors and terminals
            helix
            htop
            zellij

            # Data processing
            jq

            # Security
            _1password-cli

            # Git and version control
            gh
            jujutsu
            delta

            # Navigation and search
            entr
            tree
            zoxide
            fzf
            ripgrep
            fd
            gum

            # Development tools
            devenv
            direnv
            rclone
            bat
            watchman
            jnv
            docker
            colima

            # Shell ecosystem
            zinit
            zsh
            glow
            antigen
          ];

          myConfig.onepassword.enable = true;
          myConfig.syncthing.enable = true;

          programs.zsh.enable = true;

          environment.variables = {
            EDITOR = "helix";
            VISUAL = "helix";
          };

          environment.shellAliases = {
            # Quick system info
            sysinfo = "uname -a";

            # Git aliases
            g = "git";
            gst = "git status";
            gpush = "git push";
            gpull = "git pull";
            gd = "git diff";
            gdc = "git diff --cached";
            gco = "git checkout";
            gcob = "git checkout -b";
            gau = "git add -u";
            gauc = "git add -u && git commit -m ";
            gaum = "git add -u && git commit --amend";
            gs = "git stash";
            gsp = "git stash pop";
            gshow = "git stash show -p";
            grm = "git fetch origin && git rebase main";
            grc = "git rebase --continue";
            gm = "git merge";
            gmm = "git fetch origin && git merge origin/main";
            gf = "git fetch --prune";
            gr = "git restore --source";
            grh = "git reset --hard";
            ghv = "gh repo view --web";
            gclean = "git clean -fd";
            gkkb = ''git checkout -b $(date +"%Y%m%d%H%M%S")'';

            # Nix tools
            try = "nix-shell -p";

            # Navigation
            "..." = "cd ../..";
          };
        }
        (lib.mkIf isDarwin {
          environment.systemPackages = with pkgs; [
            google-chrome
            hidden-bar
            alacritty-theme
            home-manager
          ];
        })
      ]
      ++ lib.optionals hasHomebrew [
        (lib.mkIf isDarwin {
          homebrew = {
            enable = true;
            onActivation = {
              autoUpdate = false;
              cleanup = "uninstall";
            };
            casks = [
              "raycast"
              "zed"
              "zen"
              "ghostty"
              "deezer"
              "sensei"
              "vivaldi"
              "1password"
            ];
          };
        })
      ])
  );
}
