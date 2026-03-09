# Minimal hardware configuration for CI/testing
# Used when /etc/nixos/hardware-configuration.nix doesn't exist
{
  lib,
  modulesPath,
  ...
}: {
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
  ];

  boot = {
    loader.grub.enable = false;
    initrd.availableKernelModules = [];
    kernelModules = [];
    extraModulePackages = [];
  };

  # Minimal filesystems for evaluation
  fileSystems."/" = {
    device = "/dev/null";
    fsType = "ext4";
  };

  fileSystems."/boot" = {
    device = "/dev/null";
    fsType = "vfat";
    options = [
      "fmask=0077"
      "dmask=0077"
    ];
  };

  swapDevices = [];

  networking.useDHCP = lib.mkDefault true;
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
