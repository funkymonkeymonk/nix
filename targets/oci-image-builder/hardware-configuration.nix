{
  config,
  lib,
  pkgs,
  modulesPath,
  ...
}: {
  imports = [
    # Minimal hardware configuration for OCI image builder
    # This system doesn't require specific hardware configuration
    # as it's primarily used for container image building
  ];

  boot = {
    # Use systemd bootloader
    loader.systemd-boot.enable = true;
    loader.efi.canTouchEfiVariables = true;

    # Kernel configuration optimized for container workloads
    kernel.sysctl = {
      # Enable kernel features beneficial for container workloads
      "vm.overcommit_memory" = 1;
      "fs.inotify.max_user_watches" = 524288;
    };
  };

  fileSystems."/" = {
    device = "/dev/disk/by-uuid/CHANGE-THIS-UUID";
    fsType = "ext4";
  };

  # No special hardware requirements for container image building
  # This target is designed to be lightweight and portable
}
