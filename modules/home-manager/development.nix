{
  pkgs,
  userConfig,
  ...
}: {
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

    kitty = {
      enable = true;
      shellIntegration.enableZshIntegration = true;
    };
  };

  services.syncthing = {
    enable = true;
    overrideDevices = false;
    overrideFolders = false;
  };
}
