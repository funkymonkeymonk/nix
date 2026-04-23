# Zero - Gaming/desktop NixOS machine
# Desktop, gaming, and streaming config come from modules via extraConfig
{
  config,
  pkgs,
  lib,
  mkUser,
  inputs,
  ...
}: {
  imports =
    lib.optionals (builtins.pathExists /etc/nixos/hardware-configuration.nix) [
      /etc/nixos/hardware-configuration.nix
    ]
    ++ lib.optionals (!builtins.pathExists /etc/nixos/hardware-configuration.nix) [
      ../hardware-stub.nix
    ];

  nixpkgs.hostPlatform = "x86_64-linux";
  system.stateVersion = "25.05";

  myConfig =
    mkUser "monkey" "me@willweaver.dev"
    // {
      skills.superpowersPath = inputs.superpowers;
      roles = {
        developer.enable = true;
        desktop.enable = true;
        opencode.enable = true;
      };
      desktop = {
        enable = true;
        autoLoginUser = "monkey";
      };
      gaming.enable = true;
      streaming.enable = true;
      llmEndpoints = {
        MegamanX = {
          host = "MegamanX.local";
          port = "4000";
        };
      };
    };

  networking = {
    hostName = "zero";
    networkmanager.enable = true;
    firewall.enable = false;
  };

  time.timeZone = "America/New_York";

  environment.systemPackages = with pkgs; [
    discord
    tailscale
  ];

  # Disable sleep/hibernate (always-on machine)
  systemd.sleep.settings.Sleep = {
    AllowSuspend = false;
    AllowHibernation = false;
    AllowHybridSleep = false;
    AllowSuspendThenHibernate = false;
  };

  # NVIDIA GPU
  services.xserver.videoDrivers = ["nvidia"];
  hardware = {
    graphics.enable = true;
    nvidia = {
      open = false;
      package = config.boot.kernelPackages.nvidiaPackages.stable;
    };
  };

  # Tailscale with auto-connect
  services.tailscale.enable = true;
  systemd.services.tailscale-autoconnect = {
    description = "Automatic connection to Tailscale";
    after = ["network-pre.target" "tailscale.service"];
    wants = ["network-pre.target" "tailscale.service"];
    wantedBy = ["multi-user.target"];
    serviceConfig.Type = "oneshot";
    script = ''
      sleep 2
      status="$(${pkgs.tailscale}/bin/tailscale status -json | ${pkgs.jq}/bin/jq -r .BackendState)"
      if [ "$status" = "Running" ]; then
        exit 0
      fi
      if [ -n "$TAILSCALE_AUTH_KEY" ]; then
        ${pkgs.tailscale}/bin/tailscale up -authkey "$TAILSCALE_AUTH_KEY"
      else
        echo "Warning: TAILSCALE_AUTH_KEY not set, skipping auto-connect"
      fi
    '';
  };
}
