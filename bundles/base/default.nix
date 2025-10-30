{pkgs, ...}: {
  imports = [
    ./aliases.nix
  ];

  environment.systemPackages = with pkgs; [
    vim
    emacs
    git
    gh
    devenv
    direnv
    go-task
    rclone
    bat
    jq
    tree
    watchman
    jnv
    zinit
    fzf
    zsh
  ];

  programs.zsh = {
    enable = true;
  };
}
