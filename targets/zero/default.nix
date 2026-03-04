# Zero - Gaming/desktop NixOS machine
# Desktop, gaming, and streaming config come from modules via extraConfig
{
  config,
  pkgs,
  ...
}: {
  imports = [./hardware-configuration.nix];

  networking = {
    hostName = "zero";
    networkmanager.enable = true;
    firewall.enable = false;
  };

  time.timeZone = "America/New_York";

  # Machine-specific packages
  environment.systemPackages = with pkgs; [
    vim
    wget
    discord
    tailscale
    jq
  ];

  # Disable sleep/hibernate (always-on machine)
  systemd.sleep.extraConfig = ''
    AllowSuspend=no
    AllowHibernation=no
    AllowHybridSleep=no
    AllowSuspendThenHibernate=no
  '';

  # NVIDIA GPU
  services = {
    xserver.videoDrivers = ["nvidia"];
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

  systemd.services.tailscale-autoconnect = {
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
}
