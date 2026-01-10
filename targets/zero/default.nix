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
    ../../modules/nixos/virtual-display.nix
    ../../modules/nixos/hardware/monitor-detect.nix
    ../../modules/nixos/scripts/monitor-detect.nix
    ../../modules/nixos/scripts/display-switcher.nix
    ../../modules/nixos/scripts/resolution-switcher.nix
  ];

  # Kernel downgrade for Xbox controller compatibility (kernel 6.18.1 breaks xpadneo/xone)
  boot.kernelPackages = lib.mkForce pkgs.linuxPackages_6_17;

  # Packages
  environment.systemPackages = with pkgs; [
    vim
    wget
    unstable.lutris
    protonup-qt
    discord
    tailscale
  ];

  networking.firewall.enable = false;

  # Ensure firewall is open for Sunshine (when firewall is enabled)
  networking.firewall.allowedTCPPorts = [47989 48010];
  networking.firewall.allowedUDPPorts = [47989 48010];

  # System state version
  system.stateVersion = "25.05";

  # Sleep/hibernate policy is now handled in consolidated systemd block

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

    # Sunshine disabled - will be managed as pure systemd service
    sunshine.enable = false;

    # Virtual display server for streaming
    virtual-display = {
      enable = true;
      resolution = "3840x2160";
      user = "monkey";
    };

    # Display switching utilities
    display-switcher = {
      enable = true;
      user = "monkey";
      virtualDisplay = ":99";
    };

    # Dynamic resolution switching
    resolution-switcher = {
      enable = true;
      user = "monkey";
      virtualDisplay = ":99";
      supportedResolutions = ["3840x2160" "3440x1440" "2560x1440" "1920x1080"];
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
    # Physical monitor detection
    monitor-detect = {
      enable = true;
      user = "monkey";
      virtualDisplay = ":99";
    };

    graphics.enable = true;

    nvidia = {
      open = false;
      package = pkgs.linuxPackages_6_17.nvidiaPackages.stable;
    };

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
  # systemd helper services (consolidated systemd attribute set)
  #
  systemd = {
    # Sleep/hibernate policy
    sleep.extraConfig = ''
      AllowSuspend=no
      AllowHibernation=no
      AllowHybridSleep=no
      AllowSuspendThenHibernate=no
    '';

    # Pure systemd service for Sunshine (bypass NixOS module)
    services.sunshine-custom = {
      description = "Sunshine game streaming server";
      after = ["graphical-session.target" "virtual-display.service"];
      wants = ["graphical-session.target"];
      serviceConfig = {
        ExecStartPre = [
          # Wait a bit for virtual display to initialize
          "${pkgs.bash}/bin/sh -c 'sleep 3'"
        ];
        ExecStart = "${pkgs.unstable.sunshine}/bin/sunshine";
        Restart = "on-failure";
        RestartSec = 5;
        User = "monkey";
        Group = "users";
        WorkingDirectory = "/home/monkey";
        Environment = [
          "DISPLAY=:99"
          "XAUTHORITY=/run/user/1000/.Xauthority"
          "SUNSHINE_CLIENT_IPV4=localhost"
        ];
      };
      wantedBy = ["multi-user.target"];
    };

    # Tailscale autoconnect service
    services.tailscale-autoconnect = {
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
      serviceConfig = {
        Type = "oneshot";
        Environment = ["TAILSCALE_AUTHKEY="];
      };

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

        # otherwise authenticate with tailscale if authkey is provided
        if [ -n "$TAILSCALE_AUTHKEY" ]; then
          ${tailscale}/bin/tailscale up -authkey "$TAILSCALE_AUTHKEY"
        else
          echo "Warning: TAILSCALE_AUTHKEY not set, skipping Tailscale authentication"
        fi
      '';
    };
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
}
