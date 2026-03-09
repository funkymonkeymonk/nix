{
  inputs,
  lib,
  ...
}: {
  imports =
    lib.optionals (builtins.pathExists /etc/nixos/hardware-configuration.nix) [
      /etc/nixos/hardware-configuration.nix
    ]
    ++ lib.optionals (!builtins.pathExists /etc/nixos/hardware-configuration.nix) [
      ../hardware-stub.nix
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
