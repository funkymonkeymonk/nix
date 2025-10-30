{pkgs, ...}: {
  # macOS-specific packages and configuration
  environment.systemPackages = with pkgs; [
    # macOS-specific utilities
    google-chrome
    hidden-bar
    goose-cli
    claude-code
    alacritty-theme

    # Development tools with macOS support
    colima # Docker alternative for macOS

    # Additional system packages
    trippy
    logseq
    ripgrep
    fd
    coreutils
    clang
    slack
    home-manager
    glow
    antigen
    k3d
    kubectl
    kubernetes-helm
    k9s
    the-unarchiver
  ];

  # 1Password integration
  programs = {
    _1password.enable = true;
    _1password-gui.enable = true;
    _1password.package = pkgs.unstable._1password-cli;
    _1password-gui.package = pkgs.unstable._1password-gui;
  };
}
