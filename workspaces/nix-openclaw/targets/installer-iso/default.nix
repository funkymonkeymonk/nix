# NixOS Installer ISO Configuration
# Builds a bootable USB ISO with guided installer
{
  pkgs,
  lib,
  modulesPath,
  ...
}: {
  imports = [
    # Base minimal ISO configuration
    (modulesPath + "/installer/cd-dvd/installation-cd-minimal.nix")
  ];

  # ISO naming
  isoImage = {
    edition = "installer";
    volumeID = "NIXOS_INSTALLER";
    makeEfiBootable = true;
    makeUsbBootable = true;
  };

  # Boot loader for BIOS and UEFI
  boot.loader = {
    systemd-boot.enable = lib.mkForce false;
  };

  # Enable flakes
  nix.settings.experimental-features = ["nix-command" "flakes"];

  # System packages for the installer
  environment.systemPackages = with pkgs; [
    # TUI tools
    gum
    # Disk tools
    parted
    gptfdisk
    cryptsetup
    # Network tools
    curl
    wget
    # System info
    pciutils
    usbutils
    # Editors
    vim
    nano
    # Disko
    disko
    # Our installer
    nixos-flake-installer
    # Dev mode support
    nixos-installer-dev-mode
  ];

  # Define the installer package
  nixpkgs.config.packageOverrides = pkgs: {
    nixos-flake-installer = pkgs.callPackage ./installer.nix {};
    nixos-installer-dev-mode = pkgs.callPackage ./dev-mode.nix {};
  };

  # Auto-login on TTY1 and start installer
  services.getty = {
    autologinUser = lib.mkForce "nixos";
    greetingLine = lib.mkForce "\nWelcome to NixOS Flake Installer!\n";
    helpLine = lib.mkForce "\nThe guided installer will start automatically on TTY1.\nPress Alt+F2 for a shell.\n";
  };

  # Start installer automatically on TTY1
  systemd.services.installer-tty = {
    description = "NixOS Flake Installer TTY";
    wantedBy = ["multi-user.target"];
    after = ["systemd-user-sessions.service" "getty@tty1.service" "network-online.target"];
    wants = ["network-online.target"];
    serviceConfig = {
      Type = "simple";
      ExecStart = "${pkgs.util-linux}/bin/agetty --autologin nixos --noclear tty1 38400 linux";
      StandardInput = "tty";
      StandardOutput = "tty";
      TTYPath = "/dev/tty1";
      TTYReset = "yes";
      TTYVHangup = "yes";
      KillMode = "process";
      IgnoreSIGPIPE = "no";
      Restart = "always";
      RestartSec = "0";
    };
  };

  # Run installer after login on TTY1
  programs.bash.loginShellInit = lib.mkAfter ''
    if [ "$(tty)" = "/dev/tty1" ]; then
      # Clear screen for clean UI
      clear
      # Run the installer (with dev mode support)
      sudo ${pkgs.nixos-installer-dev-mode}/bin/nixos-installer-dev-mode
      # Don't exit to shell after installer
      read -p "Press Enter to restart..."
      sudo reboot
    fi
  '';

  # Networking
  networking = {
    hostName = "nixos-installer";
    networkmanager.enable = true;
    useDHCP = lib.mkDefault true;
  };

  # SSH for remote assistance
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "prohibit-password";
      PasswordAuthentication = false;
      PubkeyAuthentication = true;
    };
  };

  # Root user with your SSH key
  users.users.root = {
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIIxGvpCUmx1UV3K22/+sWLdRknZmlTmQgckoAUCApF8 monkey@MegamanX"
    ];
    # Empty password for initial access (installer will change this)
    initialHashedPassword = "";
  };

  # NixOS user
  users.users.nixos = {
    isNormalUser = true;
    extraGroups = ["wheel" "networkmanager"];
    # Can sudo without password for installer
  };

  # Allow passwordless sudo for installer
  security.sudo.wheelNeedsPassword = false;

  # System state
  system.stateVersion = "25.05";
}
