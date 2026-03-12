# Bootstrap NixOS configuration for new machines
# This minimal configuration gets the system running so you can:
# 1. SSH into the machine
# 2. Generate proper hardware-configuration.nix
# 3. Create a full target configuration
{
  pkgs,
  lib,
  ...
}: {
  imports = [
    # Hardware config will be generated during installation
    ./hardware-configuration.nix
    ../../modules/nixos/ghostty-terminfo.nix
  ];

  # Boot configuration
  boot.loader.grub = {
    enable = true;
    device = lib.mkDefault "/dev/sda";
    useOSProber = true;
  };

  # Networking
  networking = {
    hostName = lib.mkDefault "nixos-bootstrap";
    networkmanager.enable = true;
    firewall = {
      enable = true;
      allowedTCPPorts = [22];
    };
  };

  # Time zone
  time.timeZone = lib.mkDefault "America/New_York";

  # Internationalisation
  i18n.defaultLocale = "en_US.UTF-8";

  # Enable flakes
  nix.settings.experimental-features = ["nix-command" "flakes"];

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  # Essential system packages
  environment.systemPackages = with pkgs; [
    git
    vim
    wget
    curl
    htop
    tmux
  ];

  # Enable SSH
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = lib.mkDefault "no";
      PasswordAuthentication = lib.mkDefault false;
      PubkeyAuthentication = true;
    };
  };

  # Users will be configured by the installer script
  # The following are placeholders that get replaced

  # ADMIN_USER will be replaced with the selected admin user
  users.users.ADMIN_USER = {
    isNormalUser = true;
    description = "Admin User";
    extraGroups = ["networkmanager" "wheel"];
    shell = pkgs.zsh;
    openssh.authorizedKeys.keys = [
      # SSH_KEYS will be replaced with selected public keys
    ];
  };

  # Guest user (non-privileged)
  users.users.guest = {
    isNormalUser = true;
    description = "Guest User";
    extraGroups = ["networkmanager"];
    shell = pkgs.zsh;
    openssh.authorizedKeys.keys = [
      # SSH_KEYS will be replaced with selected public keys
    ];
  };

  # Ensure zsh is available
  programs.zsh.enable = true;

  # Sudo configuration
  security.sudo.wheelNeedsPassword = lib.mkDefault true;

  # Auto-upgrade from GitHub flake
  system.autoUpgrade = {
    enable = true;
    flake = "github:funkymonkeymonk/nix";
    flags = ["-L" "--refresh"];
    dates = "02:00";
    randomizedDelaySec = "45min";
  };

  # System state version
  system.stateVersion = "25.05";
}
