{
  config,
  pkgs,
  lib,
  ...
}: {
  networking = {
    hostName = "zero";
    networkmanager.enable = true;
  };
  time.timeZone = "America/New_York";
  services.openssh.enable = true;
  # networking.wireless.enable = true;

  imports = [
    ./hardware-configuration.nix
  ];

  services.displayManager.sddm.enable = true;
  services.displayManager.sddm.wayland.enable = true;
  services.desktopManager.plasma6.enable = true;

  services.printing.enable = true;

  # Enable sound with pipewire.
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  # Enable automatic login for the user.
  services.displayManager.autoLogin.enable = true;
  services.displayManager.autoLogin.user = "monkey";

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  environment.systemPackages = with pkgs; [
    vim # Do not forget to add an editor to edit configuration.nix! The Nano editor is also installed by default.
    wget
    lutris
    protonup-qt
    discord
    tailscale
  ];

  networking.firewall.enable = false;

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "25.05"; # Did you read the comment?

  systemd.sleep.extraConfig = ''
    AllowSuspend=no
    AllowHibernation=no
    AllowHybridSleep=no
    AllowSuspendThenHibernate=no
  '';

  services.xserver.videoDrivers = ["nvidia"];
  hardware.graphics.enable = true;
  # Temporary fix for nvidia driver issue
  boot.kernelPackages = lib.mkForce pkgs.linuxPackages_6_16;
  hardware.nvidia = {
    open = false;
    package = config.boot.kernelPackages.nvidiaPackages.stable;
  };

  programs.steam = {
    enable = true;
    remotePlay.openFirewall = true;
    gamescopeSession.enable = true;
  };

  # environment.systemPackages = with pkgs; [
  #  mangohud
  # ];

  programs.gamemode.enable = true;

  services.sunshine = {
    enable = true;
    autoStart = true;
    capSysAdmin = true; # only needed for Wayland -- omit this when using with Xorg
    openFirewall = true;
  };

  programs.kdeconnect.enable = true;

  hardware.xone.enable = true;
  hardware.xpadneo.enable = true;

  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
    settings = {
      General = {
        Experimental = true;
      };
    };
  };

  services.blueman.enable = true;

  # enable the tailscale service
  services.tailscale.enable = true;
  systemd.services.tailscale-autoconnect = {
    description = "Automatic connection to Tailscale";

    # make sure tailscale is running before trying to connect to tailscale
    after = ["network-pre.target" "tailscale.service"];
    wants = ["network-pre.target" "tailscale.service"];
    wantedBy = ["multi-user.target"];

    # set this service as a oneshot job
    serviceConfig.Type = "oneshot";

    # have the job run this shell script
    script = with pkgs; ''
      # wait for tailscaled to settle
      sleep 2

      # check if we are already authenticated to tailscale
      status="$(${tailscale}/bin/tailscale status -json | ${jq}/bin/jq -r .BackendState)"
      if [ $status = "Running" ]; then # if so, then do nothing
        exit 0
      fi

      # otherwise authenticate with tailscale
      ${tailscale}/bin/tailscale up -authkey tskey-auth-khWo2RmsVB11CNTRL-KWAvm6SydYNfQSSmAevCZNHSCaL7anaH
    '';
  };

  users.users.monkey = {
    isNormalUser = true;
    description = "monkey";
    extraGroups = ["networkmanager" "wheel"];
    shell = pkgs.zsh;
    home = "/home/monkey";
  };

  # Provide a minimal system-wide /etc/zshrc managed by Nix.
  # It sets SHELL to the Nix-provided zsh, initializes completion safely,
  # and sources the user's ~/.zshrc if present.
  environment.etc."zshrc".text = ''
    # /etc/zshrc - system-wide configuration managed by Nix
    export SHELL=${pkgs.zsh}/bin/zsh

    # Load zshenv if present (follow distribution's behavior)
    if [ -f /etc/zsh/zshenv ]; then
      . /etc/zsh/zshenv
    fi

    # Initialize completion if available (safe/optional)
    if command -v compinit >/dev/null 2>&1; then
      autoload -Uz compinit && compinit || true
    fi

    # Source user's ~/.zshrc to allow per-user customizations
    if [ -n "$HOME" ] && [ -f "$HOME/.zshrc" ]; then
      . "$HOME/.zshrc"
    fi
  '';
}
