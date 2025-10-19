{
  config,
  pkgs,
  ...
}: {
  services.jellyfin = {
    enable = true;
    package = pkgs.unstable.jellyfin;
    # Create a Jellyfin user and run as that user
    # user = "jellyfin";
  };
}
