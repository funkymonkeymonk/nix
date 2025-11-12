{pkgs, ...}: {
  home.packages = with pkgs; [
    docker
  ];

  # Ghostty configuration (installed via Homebrew)
  xdg.configFile."ghostty/config" = {
    text = ''
      # Ghostty configuration
      font-size = 14
      theme = dark:catppuccin-mocha
      window-decoration = false
      window-padding-x = 10
      window-padding-y = 6
      background-opacity = 0.95
      font-family = "JetBrains Mono"
      cursor-style = block
      shell-integration = zsh
    '';
  };

  programs = {
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

  services.syncthing.enable = true;
}
