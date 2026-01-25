{
  _config,
  pkgs,
  ...
}: {
  programs._1password = {
    enable = true;
    # Use unstable for latest versions but disable autoupdate
    package = pkgs.unstable._1password-cli;
  };
}
