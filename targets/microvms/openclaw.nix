# openclaw.nix - OpenClaw AI Assistant MicroVM
# Uses shared openclaw-server role for consistency with Lume VMs
{
  config,
  lib,
  pkgs,
  ...
}: {
  imports = [
    ../../modules/roles/openclaw-server.nix
  ];

  networking.hostName = "openclaw";

  system.autoUpgrade.enable = lib.mkForce false;

  # Microvm-specific network config
  myConfig.microvm = {
    enable = true;
    ipAddress = "192.168.83.16";
    gateway = "192.168.83.1";
  };

  # Use the shared OpenClaw server role
  myConfig.roles.openclawServer = {
    enable = true;
    port = 18789;
    # Use default openclaw user to avoid conflicts with myConfig.users "dev"
    # The openclaw-server role creates this user with isSystemUser = true
    agentModel = "zen/default";

    # Enable Discord channel
    discordChannel = {
      enable = true;
      tokenFile = "/run/secrets/openclaw-discord-bot-token";
      allowFrom = ["279110923438915586"]; # Your Discord user ID
    };

    # Enable Matrix channel for microvm environment (optional, can disable if only using Discord)
    matrixChannel = {
      enable = true;
      homeserver = "http://192.168.83.15:8008";
      userId = "@openclaw:matrix.local";
    };

    # Secrets via opnix
    secrets = {
      zenApiKeyFile = "/run/secrets/openclaw-zen-api-key";
      matrixTokenFile = "/run/secrets/openclaw-matrix-access-token";
    };

    extraConfig = {
      gateway = {
        bind = "0.0.0.0";
        verbose = true;
      };
      channels.discord.dmPolicy = "pairing";
    };
  };

  # Opnix secrets configuration
  services.onepassword-secrets = {
    enable = true;
    tokenFile = "/etc/opnix-token";

    secrets = {
      openclawZenKey = {
        reference = "op://Homelab/OpenClaw/zen-api-key";
        path = "/run/secrets/openclaw-zen-api-key";
        mode = "0600";
        owner = "dev";
        services = ["openclaw-generate-env" "openclaw-gateway"];
      };

      openclawMatrixToken = {
        reference = "op://Homelab/OpenClaw/matrix-access-token";
        path = "/run/secrets/openclaw-matrix-access-token";
        mode = "0600";
        owner = "dev";
        services = ["openclaw-generate-env" "openclaw-gateway"];
      };

      openclawDiscordToken = {
        reference = "op://Homelab/OpenClaw/discord-bot-token";
        path = "/run/secrets/openclaw-discord-bot-token";
        mode = "0600";
        owner = "dev";
        services = ["openclaw-generate-env" "openclaw-gateway"];
      };
    };
  };

  # Configure microvm for vfkit compatibility when using vfkit hypervisor
  microvm = lib.mkIf (config.microvm.hypervisor == "vfkit") {
    # Use virtiofs for shares on macOS (9p doesn't work)
    shares = lib.mkDefault [
      {
        source = "/nix/store";
        mountPoint = "/nix/.ro-store";
        tag = "ro-store";
        proto = "virtiofs";
      }
    ];

    # Note: forwardPorts only works with qemu, not vfkit
    # The vfkit runner handles networking differently
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
