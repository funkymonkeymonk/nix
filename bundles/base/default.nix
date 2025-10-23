{
  _config,
  _lib,
  pkgs,
  ...
}: {
  # Base system packages - essential tools available on all systems
  environment.systemPackages = with pkgs; [
    # Core utilities (already in modules/common/packages.nix)
    # This bundle can be empty or contain platform-specific essentials
  ];
}
