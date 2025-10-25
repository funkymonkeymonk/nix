{
  _config,
  _lib,
  pkgs,
  ...
}: {
  # Jellyfin media server
  services.jellyfin = {
    enable = true;
    package = pkgs.unstable.jellyfin;
    openFirewall = true;
  };

  # Linkwarden bookmark manager
  # Note: This would need to be configured based on the actual service setup
  # services.linkwarden = {
  #   enable = true;
  #   # ... configuration
  # };
}
