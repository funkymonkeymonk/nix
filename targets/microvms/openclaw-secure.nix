# OpenClaw Secure MicroVM - GitHub PR-Only Mode
# OpenClaw works exclusively through GitHub PRs, never touches local files directly
{pkgs, ...}: {
  # Override hostname
  networking.hostName = "openclaw-secure";

  # Create openclaw user (non-privileged)
  users.users.openclaw = {
    isNormalUser = true;
    description = "OpenClaw AI Agent (GitHub PR Mode)";
    extraGroups = [];  # No special groups
    shell = pkgs.bash;
    home = "/home/openclaw";
    openssh.authorizedKeys.keys = [];
  };

  # Root access only for maintenance
  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIIxGvpCUmx1UV3K22/+sWLdRknZmlTmQgckoAUCApF8" # MegamanX
  ];

  # Disable password login
  services.openssh.settings.PasswordAuthentication = false;

  # Time zone
  time.timeZone = "America/New_York";

  # Microvm configuration - NO repo mounts (uses GitHub instead)
  microvm = {
    hypervisor = "qemu";
    mem = 4096;
    vcpu = 2;

    # NO virtiofs shares for repos - OpenClaw uses GitHub API instead
    # Only workspace for temporary operations
    shares = [
      {
        tag = "workspace";
        source = "/tmp/openclaw-workspace";
        mountPoint = "/tmp";
        proto = "virtiofs";
      }
    ];

    # Networking - user-mode NAT
    interfaces = [
      {
        type = "user";
        id = "eth0";
        mac = "02:00:00:00:00:02";
      }
    ];

    # No persistent volumes
    volumes = [];
  };

  # Firewall - block inbound
  networking.firewall = {
    enable = true;
    # Only allow outbound (GitHub API, Discord/Telegram)
  };

  # Install minimal packages
  environment.systemPackages = with pkgs; [
    git
    gh
    vim
    htop
    curl
    jq
    openssh  # For git operations
  ];

  # Ensure 1Password CLI is available
  programs._1password.enable = true;

  # System state version
  system.stateVersion = "25.05";

  # Security banner
  systemd.services.openclaw-banner = {
    description = "OpenClaw Security Banner";
    after = ["network.target"];
    wantedBy = ["multi-user.target"];
    serviceConfig = {
      Type = "oneshot";
      StandardOutput = "journal+console";
    };
    script = ''
      echo "========================================"
      echo "OpenClaw Secure MicroVM (GitHub PR Mode)"
      echo "========================================"
      echo ""
      echo "Security Model:"
      echo "  - All changes via GitHub PRs only"
      echo "  - Target repo: funkymonkeymonk/nix"
      echo "  - PRs start as drafts"
      echo "  - PRs require review from funkymonkeymonk"
      echo "  - No direct filesystem access"
      echo "  - No arbitrary command execution"
      echo ""
      echo "AI Provider: OpenCode Zen"
      echo "  - Default model: big-pickle (free tier)"
      echo "  - Also available: claude-sonnet-4-5, gpt-5.2-codex"
      echo "  - Endpoint: https://opencode.ai/zen/v1"
      echo ""
      echo "Secrets: Configured via opnix (openclaw vault)"
      echo "  - Gateway token: op://openclaw/gateway-token"
      echo "  - GitHub PAT: op://openclaw/github-pat"
      echo "  - Zen API key: op://openclaw/opencode-zen-api-key"
      echo "========================================"
    '';
  };

  # Disable X11
  services.xserver.enable = false;

  # Ensure kernel modules for virtiofs
  boot.initrd.availableKernelModules = ["virtiofs"];
}
