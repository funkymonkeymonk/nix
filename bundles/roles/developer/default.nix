{pkgs, ...}: {
  # Developer role bundle - tools for software development
  environment.systemPackages = with pkgs; [
    # Development environments
    devenv
    direnv
    go-task

    # Text editors and IDEs
    emacs

    # Terminal utilities
    bat
    jq
    tree
    ripgrep
    fd
    htop
    watchman

    # Build tools
    clang
    python3
    nodejs
    yarn

    # Container tools
    docker
    colima
    k3d
    kubectl
    kubernetes-helm
    k9s

    # Cloud tools
    rclone

    # Shell tools
    fzf
    zinit
    antigen

    # AI Tools
    unstable.opencode
  ];
}
