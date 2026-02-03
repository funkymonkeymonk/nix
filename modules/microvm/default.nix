# Microvm module - integrates microvm.nix with our configuration
{
  config,
  lib,
  pkgs,
  ...
}: {
  # Import microvm.nix NixOS module (provided by flake)
  # The actual import happens in flake.nix via microvm.nixosModules.microvm

  microvm = {
    # Use cloud-hypervisor for good performance
    hypervisor = "cloud-hypervisor";

    # Resource allocation
    mem = 4096; # 4GB RAM
    vcpu = 4;

    # Use virtiofs for shared directories (fast, modern)
    shares = [
      {
        tag = "project";
        source = "/tmp/microvm-share";
        mountPoint = "/mnt/project";
        proto = "virtiofs";
      }
    ];

    # Networking - user-mode NAT (no root required)
    interfaces = [
      {
        type = "user";
        id = "eth0";
        mac = "02:00:00:00:00:01";
      }
    ];

    # Use tmpfs for root (ephemeral)
    volumes = [];
  };

  # Guest networking configuration
  networking = {
    hostName = lib.mkDefault "dev-vm";
    useDHCP = true;
    firewall.enable = false; # Trust host
  };

  # Enable SSH for easy access
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "yes";
      PasswordAuthentication = true;
    };
  };

  # Set root password for easy access (development only!)
  users.users.root.password = "dev";

  # Minimal packages for guest
  environment.systemPackages = with pkgs; [
    vim
    git
    htop
    curl
  ];

  # System state version
  system.stateVersion = "25.05";
}
