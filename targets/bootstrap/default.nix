# Bootstrap NixOS configuration
# Minimal configuration that works on any hardware for initial install
# After boot, the full host-specific configuration should be applied
{
  config,
  pkgs,
  lib,
  modulesPath,
  ...
}: {
  imports = [
    # Use hardware stub for evaluation during install
    # Real hardware config will be generated during install
    (modulesPath + "/installer/scan/not-detected.nix")
  ];

  boot = {
    # Boot configuration - will be overridden by hardware-config
    loader = {
      grub = {
        enable = lib.mkDefault true;
        device = lib.mkDefault "/dev/sda";
        efiSupport = lib.mkDefault false;
      };
      systemd-boot = {
        enable = lib.mkDefault false;
      };
    };
    # Essential kernel modules for most systems
    initrd.availableKernelModules = [
      "xhci_pci"
      "ahci"
      "nvme"
      "usb_storage"
      "sd_mod"
      "sr_mod"
    ];
  };

  # Minimal filesystem definition for evaluation
  # Real filesystems will come from generated hardware-config
  fileSystems."/" = {
    device = "/dev/null";
    fsType = "ext4";
  };

  # Networking - basic setup
  networking = {
    hostName = lib.mkDefault "nixos-bootstrap";
    networkmanager.enable = true;
    firewall = {
      enable = true;
      allowedTCPPorts = [22];
    };
    useDHCP = lib.mkDefault true;
  };

  # Time zone
  time.timeZone = lib.mkDefault "America/New_York";

  # Locale
  i18n.defaultLocale = "en_US.UTF-8";

  # Enable flakes
  nix.settings.experimental-features = ["nix-command" "flakes"];

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  # Essential packages for bootstrap
  environment.systemPackages = with pkgs; [
    git
    vim
    wget
    curl
    htop
    tmux
    parted
    gptfdisk
  ];

  # SSH server
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = lib.mkDefault "prohibit-password";
      PasswordAuthentication = lib.mkDefault true; # Temporarily enabled for bootstrap
      PubkeyAuthentication = true;
    };
  };

  # Users - placeholders that will be configured by installer
  users = {
    mutableUsers = false;

    # Bootstrap user with sudo access
    users.bootstrap = {
      isNormalUser = true;
      description = "Bootstrap Admin";
      extraGroups = ["networkmanager" "wheel"];
      shell = pkgs.bash;
      # Password must be set during install or via SSH keys
      hashedPassword = "$y$j9T$FmbM9Y1yQ2pXqR3sT4uV5w$xYzAbCdEfGhIjKlMnOpQrStUvWxYz0123456789AB";
      openssh.authorizedKeys.keys = [];
    };

    # Root access - use same credentials as bootstrap
    users.root = {
      inherit (config.users.users.bootstrap) hashedPassword;
      openssh.authorizedKeys.keys = config.users.users.bootstrap.openssh.authorizedKeys.keys;
    };
  };

  # Sudo without password for bootstrap (convenience)
  security.sudo.wheelNeedsPassword = lib.mkDefault false;

  # Auto-apply full configuration on first boot
  systemd.services.apply-full-config = {
    description = "Apply full NixOS configuration from flake";
    after = ["network-online.target"];
    wants = ["network-online.target"];
    wantedBy = ["multi-user.target"];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = pkgs.writeShellScript "apply-full-config" ''
        set -e
        FLAKE_URL="github:funkymonkeymonk/nix"
        HOSTNAME="$(hostname)"

        # Skip if not bootstrap
        if [[ "$HOSTNAME" != "nixos-bootstrap" ]]; then
          echo "Hostname is not bootstrap, skipping auto-apply"
          exit 0
        fi

        # Check if we can reach GitHub
        if ! curl -s --max-time 10 https://github.com > /dev/null 2>&1; then
          echo "Cannot reach GitHub, skipping auto-apply"
          echo "Run manually after network is available:"
          echo "  sudo nixos-rebuild switch --flake ''${FLAKE_URL}#<hostname>"
          exit 0
        fi

        echo "Auto-applying full configuration from ''${FLAKE_URL}..."
        # This will fail safely if hostname doesn't match a target
        nixos-rebuild switch --flake "''${FLAKE_URL}#$HOSTNAME" || true
      '';
    };
  };

  # Platform
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";

  # System state version
  system.stateVersion = "25.05";
}
