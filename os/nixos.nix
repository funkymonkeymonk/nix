# Canonical NixOS platform configuration (used by: zero)
# Note: NixOS archetypes may define their own platform defaults when they
# are not composed alongside this module.
{
  lib,
  pkgs,
  ...
}: {
  boot = {
    loader = {
      systemd-boot.enable = lib.mkDefault true;
      efi.canTouchEfiVariables = lib.mkDefault true;
    };
    kernelPackages = pkgs.linuxPackages_latest;
  };

  i18n.defaultLocale = "en_US.UTF-8";

  services.xserver.xkb.layout = "us";

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];
}
