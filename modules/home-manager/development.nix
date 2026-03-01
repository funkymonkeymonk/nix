{
  pkgs,
  osConfig,
  userConfig,
  ...
}: let
  inherit (osConfig.myConfig) isDarwin;
in {
  home.packages = with pkgs; [
    docker
  ];

  # Ghostty configuration (installed via Homebrew)
  xdg.configFile."ghostty/config" = {
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

  programs = {
    jujutsu = {
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
      };
    };

    alacritty = {
      enable = true;
      settings = {
        font.size = 14;
        window = {
          decorations = "Buttonless";
          padding = {
            x = 10;
            y = 6;
          };
          opacity = 0.95;
          class = {
            instance = "Alacritty";
            general = "Alacritty";
          };
        };
        mouse.hide_when_typing = true;
        keyboard.bindings = [
          {
            key = "Escape";
            mods = "Control|Shift";
            action = "Quit";
          }
        ];
      };
    };

    kitty = {
      enable = true;
      shellIntegration.enableZshIntegration = true;
    };

    emacs = {
      enable = true;
      package =
        if isDarwin
        then pkgs.emacs-macport
        else pkgs.emacs;
      extraConfig = ''
        (setq standard-indent 2)
      '';
    };
  };

  services.syncthing = {
    enable = true;
    overrideDevices = false;
    overrideFolders = false;
  };

  # Launch agent to keep ghostty running (Darwin only)
  launchd.agents.ghostty = {
    enable = isDarwin;
    config = {
      ProgramArguments = ["/Applications/Ghostty.app/Contents/MacOS/ghostty"];
      RunAtLoad = true;
      KeepAlive = true;
      StandardOutPath = "/tmp/ghostty-launchd.log";
      StandardErrorPath = "/tmp/ghostty-launchd.err";
    };
  };
}
