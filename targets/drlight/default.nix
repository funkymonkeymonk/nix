{inputs, ...}: {
  imports = [
    ./hardware-configuration.nix
  ];

  # Host/network/time settings for drlight
  networking = {
    hostName = "drlight";
    networkmanager.enable = true;
  };
  time.timeZone = "America/New_York";

  services.openssh.enable = true;

  system.autoUpgrade = {
    enable = true;
    flake = inputs.self.outPath;
    flags = [
      "-L"
      "--refresh"
    ];
    dates = "02:00";
    randomizedDelaySec = "45min";
  };
}
