# Generic desktop configuration for gaming/workstations.
# Hardware-specific settings belong in the consuming target module.
{
  inputs,
  lib,
  ...
}: {
  myConfig = {
    skills.superpowersPath = inputs.superpowers;
    autoUpgrade.flakeUrl = lib.mkDefault "github:funkymonkeymonk/nix#type-desktop";
  };

  nixpkgs.config.allowUnfree = true;

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  nix.settings.experimental-features = ["nix-command" "flakes"];

  networking.networkmanager.enable = true;
  networking.firewall.enable = lib.mkDefault true;

  services = {
    xserver.enable = true;
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

  programs.steam.enable = true;
  programs.steam.remotePlay.openFirewall = true;
  hardware.graphics = {
    enable = true;
    enable32Bit = true;
  };

  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "prohibit-password";
      PasswordAuthentication = false;
      AllowAgentForwarding = true;
    };
  };

  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIIxGvpCUmx1UV3K22/+sWLdRknZmlTmQgckoAUCApF8 monkey@MegamanX"
  ];

  time.timeZone = "America/New_York";
  i18n.defaultLocale = "en_US.UTF-8";
}
