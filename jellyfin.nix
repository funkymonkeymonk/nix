{
  config,
  pkgs,
  ...
}: {
  services.jellyfin = {
    enable = true;
    package = pkgs.unstable.jellyfin;
    services.jellyfin.openFirewall = true;
    # Create a Jellyfin user and run as that user
    # user = "jellyfin";
  };
}
