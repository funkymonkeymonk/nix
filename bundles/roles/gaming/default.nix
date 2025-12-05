{
  _config,
  _lib,
  pkgs,
  ...
}: {
  # Gaming role bundle - tools for gaming and entertainment
  environment.systemPackages = with pkgs; [
    moonlight-qt  # Game streaming client for playing games from remote hosts
    # Gaming platforms will be added here
    # Note: Most gaming applications are platform-specific and handled in platform bundles
  ];
}
