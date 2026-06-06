{pkgs}:
with pkgs; {
  common = [
    helix
    htop
    zellij
    yazi

    # Data processing
    jq

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
    jnv
    docker
    colima

    # Shell ecosystem
    zinit
    zsh
    antigen
  ];

  darwinOnly = [
    google-chrome
    hidden-bar
    alacritty-theme
    home-manager
  ];
}
