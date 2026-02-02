{
  _config,
  _lib,
  pkgs,
  ...
}: {
  # Jellyfin media server
  services.jellyfin = {
    enable = true;
    package = pkgs.jellyfin;
    openFirewall = true;
  };

  # Linkwarden bookmark manager
  # Note: This would need to be configured based on the actual service setup
  # services.linkwarden = {
  #   enable = true;
  #   # ... configuration
  # };

  # Mealie recipe manager
  services.mealie = {
    enable = true;
    database.createLocally = true;
    port = 9000;
  };
}
