# drlight - MicroVM Host Configuration
#
# A NixOS host optimized for running MicroVMs.
# This is the PHYSICAL MACHINE (host), not a VM.
#
# Installation scenarios:
# 1. From NixOS live CD: Partition, mount to /mnt, then:
#    nixos-generate-config --root /mnt
#    nixos-install --flake .#drlight
#
# 2. Already running NixOS:
#    sudo nixos-rebuild switch --flake .#drlight
#
{
  inputs,
  lib,
  pkgs,
  ...
}: {
  imports =
    # Hardware configuration - generated during install
    lib.optionals (builtins.pathExists /etc/nixos/hardware-configuration.nix) [
      /etc/nixos/hardware-configuration.nix
    ]
    ++ lib.optionals (!builtins.pathExists /etc/nixos/hardware-configuration.nix) [
      ../hardware-stub.nix
    ];

  # Network configuration
  networking = {
    hostName = "drlight";
    networkmanager.enable = true;
    firewall = {
      enable = true;
      allowedTCPPorts = [22]; # SSH
    };
  };

  # Time zone
  time.timeZone = "America/New_York";

  # SSH server for remote access
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "no"; # Disable root SSH access entirely
      PubkeyAuthentication = true;
      PasswordAuthentication = lib.mkDefault false;
    };
  };

  # Auto-upgrade from flake
  system.autoUpgrade = {
    enable = true;
    flake = inputs.self.outPath;
    flags = ["-L" "--refresh"];
    dates = "02:00";
    randomizedDelaySec = "45min";
  };

  # Boot configuration
  boot = {
    # Bootloader - use systemd-boot for EFI systems
    # The hardware-configuration.nix should define the /boot mount point
    loader = {
      systemd-boot.enable = lib.mkDefault true;
      efi.canTouchEfiVariables = lib.mkDefault true;
    };
    # Enable virtualization
    kernelModules = ["kvm-intel" "kvm-amd"];
  };

  # MicroVM host support - for running VMs
  environment.systemPackages = with pkgs; [
    # MicroVM tools
    qemu
    virtiofsd

    # Basic utilities
    curl
    git
    htop
    tmux
    vim
    wget
  ];

  # SSH authorized keys for monkey user (user is defined in base.nix from myConfig)
  users.users.monkey.openssh.authorizedKeys.keys = [
    # MegamanX
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIIxGvpCUmx1UV3K22/+sWLdRknZmlTmQgckoAUCApF8"
  ];

  # Disable root SSH access - must login as monkey and sudo
  users.users.root.openssh.authorizedKeys.keys = lib.mkForce [];
}
