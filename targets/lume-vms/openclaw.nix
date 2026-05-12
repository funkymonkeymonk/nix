# lume-openclaw.nix - NixOS VM configuration for Lume on Apple Silicon
# This is a NixOS configuration that runs inside a Lume macOS VM
# Designed for maximum isolation - OpenClaw runs here, not on the host
{
  lib,
  pkgs,
  ...
}:
with lib; {
  imports = [
    ../../modules/roles/openclaw-server
  ];

  # VM networking - will be bridged via Lume
  networking.hostName = "openclaw-vm";
  networking.useDHCP = true;

  # Use the shared OpenClaw server role with Discord integration
  myConfig.roles.openclawServer = {
    enable = true;
    port = 18789;

    agentModel = "inception/default";

    # Discord bot integration (matches your current openclaw-local setup)
    discordChannel = {
      enable = true;
      tokenFile = "/var/lib/openclaw/secrets/discord-bot-token";
      allowFrom = ["279110923438915586"]; # Your Discord user ID
    };

    # Inception AI API key
    secrets.zenApiKeyFile = "/var/lib/openclaw/secrets/inception-api-key";

    extraConfig = {
      gateway = {
        mode = "local";
        bind = "0.0.0.0";
      };
      channels.discord.dmPolicy = "pairing";
      agents.defaults = {
        model = "inception/default";
      };
    };
  };

  # 1Password secrets integration (opnix)
  services.onepassword-secrets = {
    enable = true;
    tokenFile = "/etc/opnix-token";

    secrets = {
      openclawDiscordToken = {
        reference = "op://openclaw/Wadsworth - Discord API Token/credential";
        path = "/var/lib/openclaw/secrets/discord-bot-token";
        mode = "0600";
        owner = "openclaw";
      };

      openclawInceptionKey = {
        reference = "op://openclaw/Inception - Open Claw/credential";
        path = "/var/lib/openclaw/secrets/inception-api-key";
        mode = "0600";
        owner = "openclaw";
      };
    };
  };

  # SSH access for management
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "no";
      PubkeyAuthentication = true;
      PasswordAuthentication = false;
    };
  };

  # Add your SSH key
  users.users.openclaw.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIIxGvpCUmx1UV3K22/+sWLdRknZmlTmQgckoAUCApF8 monkey@MegamanX"
  ];

  # Additional tools
  environment.systemPackages = with pkgs; [
    htop
    curl
    jq
    git
  ];

  # Basic system configuration
  time.timeZone = "America/New_York";
  system.stateVersion = "25.05";

  # Disable auto-upgrade (manage via Lume/nix-darwin on host)
  system.autoUpgrade.enable = lib.mkForce false;
}
