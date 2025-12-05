{
  pkgs,
  lib,
  ...
}: {
  home.packages = with pkgs; [
    docker
    # jujutsu is now managed via programs.jujutsu
  ];

  # Ghostty configuration (installed via Homebrew)
  xdg.configFile."ghostty/config" = {
    text = ''
      # Ghostty configuration
      font-size = 14
      theme = Earthsong
      window-decoration = false
      window-padding-x = 10
      window-padding-y = 6
      background-opacity = 0.95
      font-family = "JetBrains Mono"
      cursor-style = block
      shell-integration = zsh

      # Keybindings
      keybind = global:ctrl+shift+alt+t=toggle_quick_terminal

      # Keep ghostty running in background for global keybinds
      initial-window = false
      quit-after-last-window-closed = false
    '';
  };

  programs = {
    jujutsu = {
      enable = true;
      ui = {
        default = "log";
      };
      settings = {
        user = {
          name = "Will Weaver";
          email = "me@willweaver.dev";
        };
        git = {
          sign-commits = true;
          auto-rebase = true;
          push-bookmark-prefix = "push-";
          default-branch = "main";
        };
        signing = {
          program = "/Applications/1Password.app/Contents/MacOS/op-ssh-sign";
          key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIIxGvpCUmx1UV3K22/+sWLdRknZmlTmQgckoAUCApF8";
          backend = "ssh";
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

        # Dropdown terminal specific configuration
        # This will be applied when alacritty is launched with --class dropdown
        keyboard.bindings = [
          {
            key = "Escape";
            mods = "Control|Shift";
            action = "Quit";
          }
        ];

        # Window rules for dropdown terminal (handled by aerospace)
        # The aerospace config will position and size the dropdown window
      };
    };

    kitty = {
      enable = true;
      shellIntegration.enableZshIntegration = true;
    };

    emacs = {
      enable = true;
      package =
        if pkgs.stdenv.isDarwin
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
    settings = {
      devices = {
        "MegamanX" = {
          id = "YST7RD6-6IZE4J6-KUWLNXV-B32ZKEN-3TN57OE-MGY4YHU-HZUFRFW-Z7VQOQ6";
        };
        "Oldfriend" = {
          id = "7R75WU3-HTCGE6Z-AD6YCOA-HUTVJKT-PIXBDUV-JQSJITU-I6J4FFL-L4D6PQ3";
        };
        "Will's Phone" = {
          id = "652Z7Y4-72TMMIC-TKTAWNQ-5BWDWP6-DIJF2MA-7INIX5T-TY2ZOPF-SV274QH";
        };
        "wweaver" = {
          id = "Y4UMT3P-LS5AXTF-JGKJ2Z3-VI7RCRP-WQ6IO5D-5K24J2N-6WJAMEL-YIRQ6QU";
        };
      };
      folders = {};
    };
  };

  # Launch agent to keep ghostty running in background for global keybinds
  launchd.agents.ghostty = {
    enable = true;
    config = {
      ProgramArguments = ["/Applications/Ghostty.app/Contents/MacOS/ghostty"];
      RunAtLoad = true;
      KeepAlive = true;
      StandardOutPath = "/tmp/ghostty-launchd.log";
      StandardErrorPath = "/tmp/ghostty-launchd.err";
    };
  };
}
