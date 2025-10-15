{
  config,
  pkgs,
  ...
}: {
  programs._1password = {
    enable = true;
    package = pkgs.unstable._1password-cli;
  };
}
