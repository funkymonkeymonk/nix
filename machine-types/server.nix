# Generic headless server configuration
# Uses nixos-facter for automatic hardware detection
# Minimal configuration for servers
{
  pkgs,
  lib,
  inputs,
  ...
}: {
  myConfig = {
    skills.superpowersPath = inputs.superpowers;
    autoUpgrade.flakeUrl = "github:funkymonkeymonk/nix#type-server";
  };

  hardware.facter.reportPath = "/etc/nixos/facter.json";

  # REQUIRED: Configure at least one user with SSH access
  users.users.root.openssh.authorizedKeys.keys = []; # Root SSH disabled
  users.users.admin = {
    isNormalUser = true;
    extraGroups = ["wheel"];
    useDefaultShell = true;
    openssh.authorizedKeys.keys = [
      # MegamanX deploy key
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIIxGvpCUmx1UV3K22/+sWLdRknZmlTmQgckoAUCApF8 monkey@MegamanX"
    ];
  };

  # Boot configuration
  boot = {
    loader.systemd-boot.enable = lib.mkDefault true;
    loader.efi.canTouchEfiVariables = lib.mkDefault true;
    # Enable virtualization for MicroVMs
    kernelModules = ["kvm-intel" "kvm-amd"];
  };

  # Enable flakes (intentional: type-server does not include os/nixos.nix)
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

  # SSH - hardened with agent forwarding support
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "no"; # Disable root SSH entirely
      PubkeyAuthentication = true; # Keys only
      PasswordAuthentication = false; # No passwords
      AllowAgentForwarding = true; # Enable SSH agent forwarding for 1Password
    };
  };

  environment.systemPackages = with pkgs; [
    qemu
    virtiofsd
  ];

  # Locale
  time.timeZone = "America/New_York";

  # System state version
  system.stateVersion = "25.05";
}
