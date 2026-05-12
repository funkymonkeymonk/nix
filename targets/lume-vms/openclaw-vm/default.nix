# openclaw-vm.nix - Darwin VM configuration for OpenClaw
# This configuration runs inside a Lume macOS VM on protoman
# Provides OpenClaw AI gateway in an isolated environment
{
  lib,
  pkgs,
  ...
}: {
  imports = [
    ../../../modules/services/openclaw/darwin.nix
  ];

  nixpkgs.hostPlatform = "aarch64-darwin";
  system.stateVersion = 4;
  system.primaryUser = "openclaw";

  networking.hostName = "openclaw-vm";

  # Minimal system configuration
  myConfig = {
    users = [
      {
        name = "openclaw";
        email = "openclaw@willweaver.dev";
        fullName = "OpenClaw Service";
        isAdmin = true;
        sshIncludes = [];
      }
    ];

    # Minimal roles - just what's needed for OpenClaw
    roles = {
      foundation.enable = true;
      developer.enable = false;
      opencode.enable = false;
    };

    # Enable OpenCode for management if needed
    opencode = {
      enable = false;
    };

    # NOTE: 1Password secrets service is NixOS-only
    # On Darwin VMs, secrets are managed manually
    onepassword.enable = lib.mkForce false;
  };

  # OpenClaw service configuration
  services.openclaw = {
    enable = true;
    port = 18789;
    dataDir = "/var/lib/openclaw";
    user = "openclaw";
    group = "openclaw";
    openFirewall = true;

    extraConfig = {
      gateway = {
        bind = "0.0.0.0";
        verbose = true;
        mode = "local";
      };
      channels.discord = {
        enabled = true;
        dmPolicy = "pairing";
      };
      agents.defaults = {
        model = "inception/default";
        apiUrl = "https://api.inceptionlabs.ai/v1";
      };
    };
  };

  # NOTE: Secrets are managed manually on Darwin VMs
  # Create /var/lib/openclaw/secrets/ directory and place files:
  #   - discord-bot-token
  #   - inception-api-key
  # Then set the environmentFile in the OpenClaw service config
  #
  # The service will load these via environmentFile when starting

  # Create secrets directory on activation
  system.activationScripts.openclaw-secrets-dir = {
    text = ''
      echo "Creating OpenClaw secrets directory..."
      mkdir -p /var/lib/openclaw/secrets
      chown -R openclaw:openclaw /var/lib/openclaw
      chmod 750 /var/lib/openclaw/secrets
    '';
  };

  # SSH access for management
  services.openssh.enable = true;
  services.openssh.extraConfig = ''
    PermitRootLogin no
    PubkeyAuthentication yes
    PasswordAuthentication no
  '';

  # Add host SSH key for access
  users.users.openclaw.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIIxGvpCUmx1UV3K22/+sWLdRknZmlTmQgckoAUCApF8 monkey@MegamanX"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIIxGvpCUmx1UV3K22/+sWLdRknZmlTmQgckoAUCApF8 monkey@protoman"
  ];

  # Allow passwordless sudo for deploy-rs
  security.sudo.extraConfig = lib.mkForce ''
    Defaults timestamp_timeout=0
    openclaw ALL=(ALL) NOPASSWD: ALL
  '';

  # Minimal packages
  environment.systemPackages = with pkgs; [
    vim
    git
    curl
    jq
    htop
  ];

  # Log rotation
  environment.etc."newsyslog.d/openclaw.conf".text = ''
    /var/log/openclaw-gateway.log        root:wheel  644  5  10000 *  G
    /var/log/openclaw-gateway.error.log  root:wheel  644  5  10000 *  G
  '';
}
