# type-darwin-server - Generic headless Darwin server configuration
# Minimal setup for running macOS VMs via Lume
# OpenClaw runs inside a Darwin VM for isolation
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
        # Use remote LLM APIs since no local Ollama
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

  # Lume VM management scripts
  # Provides helper commands for creating and managing the OpenClaw VM
  environment.etc."lume/openclaw-vm-setup.sh".text = ''
    #!/bin/bash
    # Setup script for OpenClaw VM
    # Run this once to create the VM, then deploy with: deploy .#openclaw-vm

    set -euo pipefail

    VM_NAME="openclaw-vm"
    VM_IMAGE="macos-tahoe-vanilla:latest"

    echo "Setting up OpenClaw VM..."

    # Check if Lume is running
    if ! lume list &>/dev/null; then
      echo "ERROR: Lume daemon is not running. Start it with: lume serve"
      exit 1
    fi

    # Check if VM already exists
    if lume list | grep -q "$VM_NAME"; then
      echo "VM '$VM_NAME' already exists. Starting it..."
      lume start "$VM_NAME"
    else
      echo "Creating VM '$VM_NAME' from image '$VM_IMAGE'..."
      lume create "$VM_NAME" --image "$VM_IMAGE"
      echo "VM created. Starting it..."
      lume start "$VM_NAME"
      echo ""
      echo "=========================================="
      echo "VM created and started!"
      echo ""
      echo "Next steps:"
      echo "1. SSH into the VM: lume ssh $VM_NAME"
      echo "2. Install Nix: curl -L https://nixos.org/nix/install | sh"
      echo "3. Install nix-darwin: nix run nix-darwin/nix-darwin-24.11#darwin-rebuild -- switch --flake .#openclaw-vm"
      echo "4. Or deploy from host: deploy .#openclaw-vm"
      echo "=========================================="
    fi
  '';

  # Note: OpenClaw now runs inside a Darwin VM managed by Lume
  # The VM is a native macOS system that can run nix-darwin
  # Deploy with: deploy .#openclaw-vm
  #
  # To set up the VM for the first time:
  # 1. Ensure Lume is running: lume serve
  # 2. Create the VM: lume create openclaw-vm --image macos-tahoe-vanilla:latest
  # 3. Start the VM: lume start openclaw-vm
  # 4. SSH into the VM: lume ssh openclaw-vm
  # 5. Install Nix inside the VM: curl -L https://nixos.org/nix/install | sh
  # 6. Exit and deploy from host: deploy .#openclaw-vm

  # Log rotation for service logs using newsyslog
  environment.etc."newsyslog.d/lume-services.conf".text = ''
    # Log rotation for Lume services
    # Format: logfile owner mode count size when flags [pid_file] [sig_num]

    # Lume daemon logs
    /tmp/lume_daemon.log    root:wheel  644  5  10000 *  G
    /tmp/lume_daemon.err    root:wheel  644  5  10000 *  G
  '';
}
