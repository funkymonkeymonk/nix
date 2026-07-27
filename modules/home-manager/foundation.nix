# Foundation home-manager configuration
# Provides universal development tools on all systems
{
  lib,
  pkgs,
  userConfig,
  myConfig,
  earthsong,
  ...
}: {
  # Syncthing for file synchronization
  services.syncthing = lib.mkIf myConfig.syncthing.enable {
    enable = true;
    overrideDevices = false;
    overrideFolders = false;
  };

  # jj-hooks: runs pre-commit/prek/lefthook/hk hooks against jj bookmark
  # pushes in an ephemeral git worktree. Provides the `jj-hp` binary that
  # the `push` alias below delegates to.
  home.packages = [pkgs.jj-hooks];

  # Jujutsu version control with Earthsong color-words theme
  programs.jujutsu = lib.mkIf (userConfig.name != "") {
    enable = true;
    settings = {
      user = {
        name = userConfig.fullName;
        inherit (userConfig) email;
      };
      git = {
        sign-commits = true;
        auto-rebase = true;
        push-bookmark-prefix = "push-";
        default-branch = "main";
      };
      remotes.origin = {
        auto-track-bookmarks = "glob:*";
      };
      colors = earthsong.jjColors;
      ui = {
        editor = "hx";
      };
      aliases = {
        ba = ["bookmark" "advance"];
        # Delegate `jj push` to jj-hp, which runs the repo's configured
        # hook runner (pre-commit/prek/lefthook/hk) in an ephemeral git
        # worktree before pushing. Falls through to plain `jj git push`
        # when a repo has no hook-runner config.
        push = ["util" "exec" "--" "jj-hp" "push"];
      };
      # Automatically advance the local bookmark to the fixup commit when
      # jj-hooks autofixes files during a push (e.g. alejandra formatting).
      jj-hooks.advance-bookmarks = true;
      # Treat pushed commits as immutable. Prevents `jj squash`, `jj describe`,
      # `jj rebase`, etc. from rewriting any commit reachable from a remote
      # bookmark. See modules/home-manager/skills/external/jj/SKILL.md
      # "Pushed commits are immutable" for the design rationale.
      revset-aliases."immutable_heads()" = "present(trunk()) | remote_bookmarks()";
    };
  };

  # Helix — Earthsong custom theme
  xdg.configFile."helix/themes/earthsong.toml".text = earthsong.helixTheme;
  xdg.configFile."helix/config.toml".text = ''
    theme = "earthsong"
  '';

  # bat — Earthsong TextMate theme
  xdg.configFile."bat/themes/Earthsong.tmTheme".source = earthsong.batThemeFile;
  programs.bat = {
    enable = true;
    config.theme = "Earthsong";
  };

  # fzf — Earthsong colours + display defaults
  programs.fzf = {
    enable = true;
    defaultOptions = [
      "--height 40%"
      "--layout=reverse"
      "--border"
      "--color=${earthsong.fzfColors}"
    ];
  };

  # Ghostty terminal configuration (Darwin only)
  # Uses config.ghostty (canonical name since Ghostty 1.2.3) to avoid
  # startup config-loading issues with Ghostty 1.3.x.
  xdg.configFile."ghostty/config.ghostty" = lib.mkIf myConfig.isDarwin {
    text = ''
      font-size = 14
      theme = Earthsong
      window-decoration = false
      window-padding-x = 10
      window-padding-y = 6
      background-opacity = 0.95
      font-family = "JetBrains Mono"
      cursor-style = block
      shell-integration = zsh
      keybind = global:ctrl+shift+alt+t=toggle_quick_terminal
      initial-window = false
      quit-after-last-window-closed = false
      shell-integration-features = ssh-env,ssh-terminfo
    '';
  };
}
