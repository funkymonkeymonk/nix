# Foundation home-manager configuration
# Provides universal development tools on all systems
{
  config,
  lib,
  userConfig,
  ...
}: {
  # Syncthing for file synchronization
  services.syncthing = lib.mkIf config.myConfig.syncthing.enable {
    enable = true;
    overrideDevices = false;
    overrideFolders = false;
  };

  # Jujutsu version control with basic configuration
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
    };
  };

  # Ghostty terminal configuration
  xdg.configFile."ghostty/config".text = lib.mkIf config.myConfig.isDarwin ''
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
}
