# Zero - Gaming/desktop NixOS machine (NVMe + NVIDIA + AMD CPU)
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
        tailscale.enable = true;
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
      onepassword.enable = true;
    };

  networking = {
    hostName = "zero";
    networkmanager.enable = true;
    firewall.enable = false;
  };

  time.timeZone = "America/New_York";

  environment.systemPackages = with pkgs; [
    discord
  ];

  # Hardware: NVMe, AMD CPU, NVIDIA GPU
  boot.initrd.availableKernelModules = [
    "nvme"
    "xhci_pci"
    "ahci"
    "usbhid"
    "usb_storage"
    "sd_mod"
  ];
  hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;

  # Disable sleep/hibernate (always-on machine)
  systemd.sleep.settings.Sleep = {
    AllowSuspend = false;
    AllowHibernation = false;
    AllowHybridSleep = false;
    AllowSuspendThenHibernate = false;
  };

  # NVIDIA GPU
  services.xserver.videoDrivers = ["nvidia"];
  hardware = {
    graphics.enable = true;
    nvidia = {
      open = false;
      package = config.boot.kernelPackages.nvidiaPackages.stable;
    };
  };
}
