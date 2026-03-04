{
  config,
  inputs,
  pkgs,
  ...
}:
# NixOS module for the `drlight` machine.
# - Configures basic networking / SSH settings used in flake.nix
# - Runs Jellyfin and Mealie services
# Note: User configuration comes from modules/nixos/base.nix via myConfig.users
{
  imports = [
    ./hardware-configuration.nix
    ../../modules/nixos/services.nix
  ];

  # Machine-specific packages
  environment.systemPackages = with pkgs; [
    tailscale
    jq
  ];

  # Host/network/time settings for drlight
  networking = {
    hostName = "drlight";
    networkmanager.enable = true;
    firewall.allowedTCPPorts = [8000 9000];
  };
  time.timeZone = "America/New_York";

  services = {
    openssh.enable = true;
    tailscale.enable = true;

    onepassword-secrets = {
      enable = true;
      tokenFile = "/etc/opnix-token";
      secrets = {
        tailscaleAuthKey = {
          reference = "op://Homelab/Tailscale/auth-key";
          services = ["tailscale-autoconnect"];
        };
      };
    };
  };

  system.autoUpgrade = {
    enable = true;
    flake = inputs.self.outPath;
    flags = ["-L"];
    dates = "02:00";
    randomizedDelaySec = "45min";
  };

  # Automatically update flake inputs to latest (nix flake update)
  # This runs at 1:00 AM and updates flake.lock to latest on main branches
  systemd = {
    services = {
      flake-autoupdate = {
        description = "Update Nix flake inputs to latest";
        path = [pkgs.git pkgs.nix];
        serviceConfig = {
          Type = "oneshot";
          User = "monkey";
          Environment = "HOME=/home/monkey";
          WorkingDirectory = "/home/monkey/repos/nix";
          ExecStart = "${pkgs.nix}/bin/nix flake update";
        };
      };

      # Tailscale with auto-connect using opnix secret
      tailscale-autoconnect = {
        description = "Automatic connection to Tailscale";
        after = ["network-pre.target" "tailscale.service" "opnix-secrets.service"];
        wants = ["network-pre.target" "tailscale.service" "opnix-secrets.service"];
        wantedBy = ["multi-user.target"];
        serviceConfig.Type = "oneshot";
        script = ''
          sleep 2
          status="$(${pkgs.tailscale}/bin/tailscale status -json | ${pkgs.jq}/bin/jq -r .BackendState)"
          if [ "$status" = "Running" ]; then
            exit 0
          fi
          authKeyFile="${config.services.onepassword-secrets.secretPaths.tailscaleAuthKey}"
          if [ -f "$authKeyFile" ]; then
            authKey=$(cat "$authKeyFile")
            ${pkgs.tailscale}/bin/tailscale up -authkey "$authKey"
          else
            echo "Warning: Tailscale auth key file not found at $authKeyFile"
            echo "Run 'opnix token set' and ensure the secret is configured in 1Password"
          fi
        '';
      };
    };

    timers.flake-autoupdate = {
      description = "Timer for flake autoupdate";
      wantedBy = ["timers.target"];
      timerConfig = {
        OnCalendar = "01:00";
        RandomizedDelaySec = "30min";
      };
    };
  };
}
