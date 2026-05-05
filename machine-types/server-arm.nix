# Generic headless ARM64 server configuration
# Uses nixos-facter for automatic hardware detection
# Minimal configuration for ARM servers
{
  pkgs,
  lib,
  inputs,
  ...
}: {
  myConfig = {
    skills.superpowersPath = inputs.superpowers;
    autoUpgrade.flakeUrl = "github:funkymonkeymonk/nix#type-server-arm";
  };

  hardware.facter.reportPath = "/etc/nixos/facter.json";

  # REQUIRED: Configure at least one user with SSH access
  users.users.root.openssh.authorizedKeys.keys = [];
  users.users.monkey = {
    isNormalUser = true;
    extraGroups = ["wheel"];
    useDefaultShell = true;
    openssh.authorizedKeys.keys = [
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

  # Enable flakes (intentional: type-server-arm does not include os/nixos.nix)
  nix.settings.experimental-features = ["nix-command" "flakes"];

  # Networking - DHCP for IP and hostname
  networking = {
    useDHCP = lib.mkDefault true;
    dhcpcd.extraConfig = ''
      option host_name
      send host-name = ""
    '';
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
      PermitRootLogin = "no";
      PubkeyAuthentication = true;
      PasswordAuthentication = false;
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
