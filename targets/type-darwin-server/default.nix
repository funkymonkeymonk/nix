# type-darwin-server - Generic headless Darwin server configuration
# Minimal setup for running macOS VMs via Lume.
{
  mkUser,
  inputs,
  pkgs,
  lib,
  ...
}: {
  nixpkgs.hostPlatform = "aarch64-darwin";
  system.stateVersion = 4;
  system.primaryUser = "monkey";

  myConfig =
    mkUser "monkey" "me@willweaver.dev"
    // {
      skills.superpowersPath = inputs.superpowers;
      roles = {
        developer.enable = true; # Basic dev tools for VM management
        opencode.enable = true; # AI assistant for management tasks
      };
      opencode = {
        enable = true;
        # Use remote LLM APIs since there's no local inference server on this host
        model = null; # User will select on first run
      };
      llmClient.rtk.enable = true;
      lume = {
        enable = true;
        enableBackgroundService = true;
        port = 7777;
        enableAutoUpdater = true;
        # Pre-pull macOS Tahoe vanilla image for quick VM creation
        prePullImages = ["macos-tahoe-vanilla:latest"];
      };
    };

  # SSH server (Darwin doesn't support services.openssh.settings, use extraConfig for hardening)
  services.openssh.enable = true;
  services.openssh.extraConfig = ''
    PermitRootLogin no
    PubkeyAuthentication yes
    PasswordAuthentication no
  '';

  # Note: Using Determinate Nix which manages its own daemon
  # Cannot use nix-darwin's nix.linux-builder with Determinate
  # Will set up Linux builder manually or use alternative approach

  # Add MegamanX SSH key for passwordless login
  users.users.monkey.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIIxGvpCUmx1UV3K22/+sWLdRknZmlTmQgckoAUCApF8 monkey@MegamanX"
  ];

  # Allow passwordless sudo for deploy-rs automated deployments
  # This is required because deploy-rs activates the system over SSH
  # and needs to run sudo commands on the remote host
  security.sudo.extraConfig = lib.mkForce ''
    Defaults timestamp_timeout=0
    monkey ALL=(ALL) NOPASSWD: ALL
  '';

  # VM management tools - just Lume for macOS VMs
  environment.systemPackages = with pkgs; [
    curl # For downloading VM images
    jq # For parsing Lume API responses
  ];

  # Log rotation for service logs using newsyslog
  environment.etc."newsyslog.d/lume-services.conf".text = ''
    # Log rotation for Lume services
    # Format: logfile owner mode count size when flags [pid_file] [sig_num]

    # Lume daemon logs
    /tmp/lume_daemon.log    root:wheel  644  5  10000 *  G
    /tmp/lume_daemon.err    root:wheel  644  5  10000 *  G
  '';
}
