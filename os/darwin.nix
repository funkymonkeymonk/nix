{
  _config,
  pkgs,
  ...
}: {
  nix.enable = false;

  # Enable auto-migration for nix-homebrew by default
  nix-homebrew.autoMigrate = true;

  # Require password for each sudo command
  security.sudo.extraConfig = ''
    Defaults timestamp_timeout=0
  '';

  system.defaults = {
    NSGlobalDomain.AppleInterfaceStyle = "Dark";
    dock = {
      autohide = true;
    };
  };
}
