{
  _config,
  pkgs,
  ...
}: {
  nix.enable = false;

  system.defaults = {
    NSGlobalDomain.AppleInterfaceStyle = "Dark";
    dock = {
      autohide = true;
    };
  };

  environment.systemPackages = with pkgs; [
    google-chrome
    trippy
    logseq
    ripgrep
    fd
    coreutils
    clang
    slack
    home-manager
    colima
    hidden-bar
    glow
    goose-cli
    antigen
    alacritty-theme
    #atuin - check this out later
    claude-code
    k3d
    kubectl
    kubernetes-helm
    k9s
    the-unarchiver
  ];
}
