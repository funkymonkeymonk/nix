# openclaw.nix - OpenClaw AI Assistant MicroVM
# Uses official nix-openclaw module with shared configuration
# https://github.com/openclaw/openclaw
{
  config,
  lib,
  pkgs,
  ...
}: {
  networking.hostName = "openclaw";

  system.autoUpgrade.enable = lib.mkForce false;

  # Microvm-specific network config
  myConfig.microvm = {
    enable = true;
    ipAddress = "192.168.83.16";
    gateway = "192.168.83.1";
  };

  # Enable OpenClaw with shared configuration
  myConfig.openclaw = {
    enable = true;
    user = "agent";
    port = 18789;
    openFirewall = true;

    # Matrix integration - connects to the Matrix microvm
    matrix = {
      enable = true;
      homeserver = "http://192.168.83.15:8008";
      userId = "@openclaw:matrix.local";
      # Access token will be loaded from secrets
      accessTokenFile = "/run/secrets/openclaw-matrix-access-token";
    };

    model = "zen/default";

    # Additional environment file for API keys
    environmentFiles = [];
  };

  # Opnix secrets configuration for Matrix token and Zen API key
  services.onepassword-secrets = {
    enable = true;
    tokenFile = "/etc/opnix-token";

    secrets = {
      openclawZenKey = {
        reference = "op://Homelab/OpenClaw/zen-api-key";
        path = "/run/secrets/openclaw-zen-api-key";
        mode = "0600";
        owner = "agent";
        services = ["openclaw-generate-env" "openclaw-gateway"];
      };

      openclawMatrixToken = {
        reference = "op://Homelab/OpenClaw/matrix-access-token";
        path = "/run/secrets/openclaw-matrix-access-token";
        mode = "0600";
        owner = "agent";
        services = ["openclaw-generate-env" "openclaw-gateway"];
      };
    };
  };

  # Add Zen API key to environment
  systemd.services.openclaw-generate-env = lib.mkIf config.myConfig.openclaw.enable {
    script = lib.mkAfter ''
      # Append Zen API key to generated env file
      ZEN_KEY=$(cat /run/secrets/openclaw-zen-api-key 2>/dev/null || echo "zen_placeholder")
      echo "ZEN_API_KEY=$ZEN_KEY" >> /run/openclaw/generated-env
    '';
  };

  environment.systemPackages = with pkgs; [
    vim
    git
    gh
    htop
    curl
    jq
  ];

  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIIxGvpCUmx1UV3K22/+sWLdRknZmlTmQgckoAUCApF8"
  ];

  time.timeZone = "America/New_York";
  system.stateVersion = "25.05";
}
