# Canonical NixOS platform configuration (used by: zero)
# Note: machine-types/* and os/microvm.nix define their own copies since they
# are NOT included alongside this file in any nixosConfiguration.
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
