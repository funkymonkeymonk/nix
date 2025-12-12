{pkgs, ...}: {
  # Developer role bundle - tools for software development
  environment.systemPackages = with pkgs; [
    # Text editors and IDEs
    emacs

    # Terminal utilities
    ripgrep
    fd
    htop

    # Build tools
    clang
    python3
    nodejs
    yarn

    # Container tools
    docker
    # colima
    k3d
    kubectl
    kubernetes-helm
    k9s

    # Cloud tools
    rclone

    # Shell tools
    antigen

    # AI Tools
    unstable.opencode
  ];
}
