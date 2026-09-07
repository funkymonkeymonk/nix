# Zero - Gaming/desktop NixOS machine (NVMe + AMD CPU/GPU)
{
  config,
  pkgs,
  lib,
  mkUser,
  inputs,
  modulesPath,
  ...
}: {
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
  ];

  nixpkgs.hostPlatform = "x86_64-linux";
  system.stateVersion = "25.05";

  myConfig =
    mkUser "monkey" "me@willweaver.dev"
    // {
      skills.superpowersPath = inputs.superpowers;
      autoUpgrade.flakeUrl = "github:funkymonkeymonk/nix#zero";
      roles = {
        developer.enable = true;
        desktop.enable = true;
        opencode.enable = true;
      };
      tailscale = {
        enable = true;
        authKeyOpnixItem = "Tailscale Auth Key/credential";
      };
      desktop = {
        enable = true;
        autoLoginUser = "monkey";
      };
      gaming.enable = true;
      streaming.enable = true;
      llmEndpoints = {
        MegamanX = {
          host = "MegamanX.local";
          port = "4000";
        };
      };
      onepassword = {
        enable = true;
        defaultVault = "Homelab";
      };
    };

  networking = {
    hostName = "zero";
    networkmanager.enable = true;
    firewall.enable = false;
  };

  time.timeZone = "America/New_York";

  environment.systemPackages = with pkgs; [
    discord

    # Hardware-specific packages for connected peripherals
    liquidctl # Corsair H100i RGB PRO XT AIO cooling control
    openrgb # IT8297 RGB LED controller on motherboard
    openrazer-daemon # Razer Naga Trinity mouse (driver userspace)
    polychromatic # GUI for openrazer device management
    nvme-cli # Samsung NVMe SSD diagnostics
    smartmontools # Drive health monitoring
    v4l-utils # Logitech C920 webcam (v4l2-ctl)
    amdgpu_top # AMD GPU monitoring
    libva-utils # AMD GPU VA-API diagnostics (vainfo)
    vulkan-tools # AMD GPU Vulkan diagnostics (vulkaninfo)
    pciutils # Hardware debug (lspci)
    usbutils # Hardware debug (lsusb)
  ];

  # Razer Naga Trinity mouse support (udev rules + userspace daemon)
  hardware.openrazer = {
    enable = true;
    users = ["monkey"];
  };

  # Hardware: NVMe, AMD CPU/GPU
  boot.initrd.availableKernelModules = [
    "nvme"
    "xhci_pci"
    "ahci"
    "usbhid"
    "usb_storage"
    "sd_mod"
  ];
  boot.initrd.kernelModules = ["amdgpu"];
  services.xserver.videoDrivers = ["amdgpu"];
  hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;

  # Disable sleep/hibernate (always-on machine)
  systemd.sleep.settings.Sleep = {
    AllowSuspend = false;
    AllowHibernation = false;
    AllowHybridSleep = false;
    AllowSuspendThenHibernate = false;
  };
}
