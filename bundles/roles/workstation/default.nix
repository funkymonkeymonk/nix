{
  _config,
  _lib,
  pkgs,
  ...
}: {
  # Workstation role bundle - general productivity tools
  environment.systemPackages = with pkgs; [
    # Productivity tools
    logseq
    slack
    trippy

    # System utilities
    coreutils
    the-unarchiver
  ];
}
