{pkgs, ...}: {
  boot = {
    loader = {
      systemd-boot.enable = true;
      efi.canTouchEfiVariables = true;
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
