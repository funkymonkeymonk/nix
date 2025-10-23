{
  _config,
  _lib,
  ...
}: {
  # Jellyfin media server
  services.jellyfin = {
    enable = true;
    openFirewall = true;
  };

  # Linkwarden bookmark manager
  # Note: This would need to be configured based on the actual service setup
  # services.linkwarden = {
  #   enable = true;
  #   # ... configuration
  # };
}
