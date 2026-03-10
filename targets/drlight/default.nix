# drlight - NixOS configuration for existing NixOS systems only
# This configuration assumes you're running on an already-installed NixOS
# machine with a valid /etc/nixos/hardware-configuration.nix
# It will NOT work from a Live USB or fresh install - use the bootstrap
# configuration for that instead.
{inputs, ...}: {
  imports = [
    # Requires existing hardware configuration - will fail if this doesn't exist
    /etc/nixos/hardware-configuration.nix
  ];

  # Host/network/time settings for drlight
  networking = {
    hostName = "drlight";
    networkmanager.enable = true;
  };
  time.timeZone = "America/New_York";

  services.openssh.enable = true;

  # Auto-upgrade from this flake
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
