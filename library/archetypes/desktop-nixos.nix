{
  inputs,
  lib,
  ...
}: {
  imports = [];

  myConfig = {
    skills.superpowersPath = inputs.superpowers or null;
  };

  nixpkgs.config.allowUnfree = true;

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  nix.settings.experimental-features = ["nix-command" "flakes"];

  networking.networkmanager.enable = true;
  networking.firewall.enable = lib.mkDefault true;

  services = {
    xserver = {
      enable = true;
    };
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

  users.users.root.openssh.authorizedKeys.keys = [];

  time.timeZone = "America/New_York";
  i18n.defaultLocale = "en_US.UTF-8";

  system.stateVersion = "25.05";
}
