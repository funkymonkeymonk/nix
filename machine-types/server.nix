# Generic headless server configuration
# Uses nixos-facter for automatic hardware detection
# Minimal configuration for servers
{
  pkgs,
  lib,
  ...
}: {
  # Boot configuration
  boot = {
    loader.systemd-boot.enable = lib.mkDefault true;
    loader.efi.canTouchEfiVariables = lib.mkDefault true;
    # Enable virtualization for MicroVMs
    kernelModules = ["kvm-intel" "kvm-amd"];
  };

  # Enable flakes
  nix.settings.experimental-features = ["nix-command" "flakes"];

  # Networking - DHCP for IP and hostname
  networking = {
    useDHCP = lib.mkDefault true;
    # Accept hostname from DHCP server (takeout container pattern)
    dhcpcd.extraConfig = ''
      option host_name
      send host-name = ""
    '';
    # Firewall - allow SSH
    firewall = {
      enable = true;
      allowedTCPPorts = [22];
    };
  };

  # No desktop environment
  services.xserver.enable = false;

  # SSH - hardened
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "no"; # Disable root SSH entirely
      PubkeyAuthentication = true; # Keys only
      PasswordAuthentication = false; # No passwords
    };
  };

  # Essential packages for headless server
  environment.systemPackages = with pkgs; [
    vim
    git
    htop
    tmux
    # MicroVM support
    qemu
    virtiofsd
  ];

  # Auto-upgrade from GitHub (takeout container pattern)
  system.autoUpgrade = {
    enable = true;
    flake = "github:funkymonkeymonk/nix#type-server";
    flags = ["--refresh"];
    dates = "02:00";
    randomizedDelaySec = "45min";
  };

  # Locale
  time.timeZone = "America/New_York";

  # System state version
  system.stateVersion = "25.05";
}
