{
  config,
  pkgs,
  lib,
  ...
}: {
  # Networking & basic system settings
  networking = {
    hostName = "zero";
    networkmanager.enable = true;
  };

  time.timeZone = "America/New_York";

  imports = [
    ./hardware-configuration.nix
  ];

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  # Packages
  environment.systemPackages = with pkgs; [
    vim
    wget
    lutris
    protonup-qt
    discord
    tailscale
  ];

  networking.firewall.enable = false;

  # System state version
  system.stateVersion = "25.05";

  # Sleep/hibernate policy
  systemd.sleep.extraConfig = ''
    AllowSuspend=no
    AllowHibernation=no
    AllowHybridSleep=no
    AllowSuspendThenHibernate=no
  '';

  # Kernel / boot overrides
  boot.kernelPackages = lib.mkForce pkgs.linuxPackages_6_16;

  # Security/runtime
  security.rtkit.enable = true;

  #
  # Consolidated `services` attribute set
  #
  services = {
    # SSH
    openssh.enable = true;

    # Display manager & desktop
    displayManager = {
      sddm = {
        enable = true;
        wayland.enable = true;
      };
      autoLogin = {
        enable = true;
        user = "monkey";
      };
    };

    desktopManager.plasma6.enable = true;

    # Printing
    printing.enable = true;

    # Audio
    pulseaudio.enable = false;

    pipewire = {
      enable = true;
      alsa.enable = true;
      alsa.support32Bit = true;
      pulse.enable = true;
    };

    # X / graphics-related services
    xserver = {
      videoDrivers = ["nvidia"];
    };

    # Sunshine (game streaming)
    sunshine = {
      enable = true;
      autoStart = true;
      capSysAdmin = true; # only needed for Wayland -- omit this when using with Xorg
      openFirewall = true;
    };

    # Bluetooth helpers
    blueman = {
      enable = true;
    };

    # Tailscale
    tailscale = {
      enable = true;
    };

    # Keep a placeholder so other modules that reference services.sunshine still work
    # (the actual value is defined above).
  };

  #
  # Consolidated `hardware` attribute set
  #
  hardware = {
    graphics.enable = true;

    nvidia = {
      open = false;
      package = config.boot.kernelPackages.nvidiaPackages.stable;
    };

    xone.enable = true;
    xpadneo.enable = true;

    bluetooth = {
      enable = true;
      powerOnBoot = true;
      settings = {
        General = {
          Experimental = true;
        };
      };
    };
  };

  #
  # Consolidated `programs` attribute set
  #
  programs = {
    steam = {
      enable = true;
      remotePlay.openFirewall = true;
      gamescopeSession.enable = true;
    };

    gamemode = {
      enable = true;
    };

    kdeconnect = {
      enable = true;
    };
  };

  #
  # systemd helper service (left at top-level as a systemd service)
  #
  systemd.services.tailscale-autoconnect = {
    description = "Automatic connection to Tailscale";

    # make sure tailscale is running before trying to connect to tailscale
    after = [
      "network-pre.target"
      "tailscale.service"
    ];
    wants = [
      "network-pre.target"
      "tailscale.service"
    ];
    wantedBy = ["multi-user.target"];

    # set this service as a oneshot job
    serviceConfig.Type = "oneshot";

    # have the job run this shell script
    script = with pkgs; ''
      # wait for tailscaled to settle
      sleep 2

      # check if we are already authenticated to tailscale
      status="$(${tailscale}/bin/tailscale status -json | ${jq}/bin/jq -r .BackendState)"
      if [ "$status" = "Running" ]; then
        # if so, then do nothing
        exit 0
      fi

      # otherwise authenticate with tailscale
      ${tailscale}/bin/tailscale up -authkey tskey-auth-khWo2RmsVB11CNTRL-KWAvm6SydYNfQSSmAevCZNHSCaL7anaH
    '';
  };

  #
  # Users
  #
  users.users.monkey = {
    isNormalUser = true;
    description = "monkey";
    extraGroups = [
      "networkmanager"
      "wheel"
    ];
    shell = pkgs.zsh;
    home = "/home/monkey";
  };

  #
  # /etc/zshrc managed by Nix
  #
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
