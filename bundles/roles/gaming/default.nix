{
  _config,
  _lib,
  pkgs,
  ...
}: {
  # Gaming role bundle - tools for gaming and entertainment
  environment.systemPackages = with pkgs; [
    moonlight-qt
    # Gaming platforms will be added here
    # Note: Most gaming applications are platforam-specific and handled in platform bundles
  ];
}
