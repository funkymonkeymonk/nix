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

  # Disable 1Password GUI autoupdater while keeping latest versions
  home.file."Library/Group Containers/2BUA8C4S2C.com.1password/settings.json".text = ''
    {
      "updateChannel": "stable",
      "autoUpdate": false
    }
  '';
}
