# Generic desktop configuration for gaming/workstations
# Uses nixos-facter for automatic hardware detection
# No hardware-configuration.nix required!
{inputs, ...}: {
  imports = [
    # Hardware detection - replaces hardware-configuration.nix
    # This is populated automatically during installation
    # { hardware.facter.reportPath = ./facter.json; }
  ];

  myConfig = {
    skills.superpowersPath = inputs.superpowers;
    autoUpgrade.flakeUrl = "github:funkymonkeymonk/nix#type-desktop";
  };

  # Allow unfree packages (Steam, NVIDIA drivers, etc.)
  nixpkgs.config.allowUnfree = true;

  # Boot
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Enable flakes (intentional: type-desktop does not include os/nixos.nix)
  nix.settings.experimental-features = ["nix-command" "flakes"];

  # Networking
  networking.networkmanager.enable = true;
  networking.firewall.enable = true;

  # Desktop environment
  services = {
    xserver = {
      enable = true;
      displayManager.gdm.enable = true;
      desktopManager.gnome.enable = true;
    };

    # Audio
    pulseaudio.enable = false;
    pipewire = {
      enable = true;
      alsa.enable = true;
      alsa.support32Bit = true;
      pulse.enable = true;
      jack.enable = true;
    };
  };

  security.rtkit.enable = true;

  # Graphics - nixos-facter will auto-detect and configure NVIDIA/AMD/Intel
  # You can add manual overrides here if needed

  # Gaming
  programs.steam.enable = true;
  programs.steam.remotePlay.openFirewall = true;
  hardware.graphics = {
    enable = true;
    enable32Bit = true;
  };

  # SSH with agent forwarding support
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "prohibit-password";
      PasswordAuthentication = false;
      AllowAgentForwarding = true; # Enable SSH agent forwarding for 1Password
    };
  };

  # SSH keys for initial access (replace with your key)
  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIIxGvpCUmx1UV3K22/+sWLdRknZmlTmQgckoAUCApF8 monkey@MegamanX"
  ];

  # User will be created by your user module
  # This is just the base system

  # Locale
  time.timeZone = "America/New_York";
  i18n.defaultLocale = "en_US.UTF-8";

  # System state version
  system.stateVersion = "25.05";
}
