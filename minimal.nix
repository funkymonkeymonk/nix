{
  config,
  pkgs,
  ...
}: {
  environment.systemPackages = with pkgs; [
    vim
    emacs
    git
    gh
    devenv
    direnv
    go-task
    the-unarchiver
    rclone
    bat
    jq
    tree
    watchman
    jnv
    zinit
    fzf
  ];
}
