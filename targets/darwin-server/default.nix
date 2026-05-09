# darwin-server target configuration
# Headless Darwin (macOS) server for macOS VM management via Lume
# Hardware: Mac M4 with 24GB RAM
# Primary User: monkey (admin)
{
  mkUser,
  inputs,
  pkgs,
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
        developer.enable = true;
        opencode.enable = true;
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
        # Pre-pull macOS Tahoe vanilla image
        prePullImages = ["macos-tahoe-vanilla:latest"];
      };
      # 1Password Connect Server for MicroVM secret access
      # Provides REST API for scaled secret management with per-VM access control
      onepassword-connect = {
        enable = true;
        port = 8080;
        credentialsFile = "/etc/1password-connect-credentials";
      };
    };

  # Enable SSH server for remote access
  services.openssh.enable = true;

  # Add MegamanX SSH key for passwordless login
  users.users.monkey.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIIxGvpCUmx1UV3K22/+sWLdRknZmlTmQgckoAUCApF8 monkey@MegamanX"
  ];

  # OPNIX configuration for darwin-server
  # Fetches secrets for local use and for MicroVMs
  services.onepassword-secrets = {
    enable = true;
    tokenFile = "/etc/opnix-token";
    secrets = {
      # OpenClaw service account token - mounted to MicroVM
      openclawServiceAccount = {
        reference = "op://Service Accounts/1Password Service Account Auth Token: Openclaw/credential";
        path = "/var/lib/opnix/secrets/openclaw-token";
        mode = "0600";
      };
    };
  };

  # Copy OpenClaw token for MicroVM mount
  system.activationScripts.openclaw-credentials = {
    text = ''
      echo "Setting up OpenClaw credentials..."
      OPNIX_TOKEN="/var/lib/opnix/secrets/openclaw-token"
      VM_TOKEN="/tmp/openclaw-vfkit-opnix-token"

      if [[ -f "$OPNIX_TOKEN" ]]; then
        cp "$OPNIX_TOKEN" "$VM_TOKEN"
        chmod 600 "$VM_TOKEN"
        echo "OpenClaw token prepared for MicroVM"
      elif [[ ! -f "$VM_TOKEN" ]]; then
        echo "WARNING: OpenClaw token not found at $OPNIX_TOKEN"
        echo "Place token manually at $VM_TOKEN or configure opnix"
        echo "Secret reference: op://Service Accounts/OpenClaw MicroVM/credential"
      fi
    '';
  };

  # OpenClaw vfkit MicroVM launchd service
  launchd.daemons.openclaw-vfkit = {
    serviceConfig = {
      Label = "com.funkymonkey.openclaw-vfkit";
      ProgramArguments = [
        "/bin/sh"
        "-c"
        ''
          set -e
          LOG_DIR="/Users/monkey/Library/Logs"

          mkdir -p "$LOG_DIR"

          # Start the microvm
          echo "$(date '+%Y-%m-%d %H:%M:%S') Starting openclaw-vfkit microvm..." >> "$LOG_DIR/openclaw-vfkit.log"
          exec /run/current-system/sw/bin/nix run github:funkymonkeymonk/nix/feat/openclaw-vfkit#microvm-openclaw-vfkit --impure 2>> "$LOG_DIR/openclaw-vfkit.log"
        ''
      ];
      EnvironmentVariables = {
        PATH = "/run/current-system/sw/bin:/usr/local/bin:/usr/bin:/bin";
      };
      StandardOutPath = "/Users/monkey/Library/Logs/openclaw-vfkit.stdout";
      StandardErrorPath = "/Users/monkey/Library/Logs/openclaw-vfkit.stderr";
      RunAtLoad = true;
      KeepAlive = true;
    };
  };

  # Cloud-init support - apply configuration from /etc/cloud-init.yaml
  # Applied on boot via launchd
  launchd.daemons.apply-cloud-init = {
    serviceConfig = {
      Label = "com.funkymonkeymonk.cloud-init";
      ProgramArguments = [
        "${pkgs.bash}/bin/bash"
        "-c"
        ''
          set -e
          CONFIG_FILE="/etc/cloud-init.yaml"
          LOG_FILE="/var/log/cloud-init.log"

          log() {
            echo "$(date '+%Y-%m-%d %H:%M:%S') $1" | tee -a "$LOG_FILE"
          }

          if [[ -f "$CONFIG_FILE" ]]; then
            log "Applying cloud-init configuration from $CONFIG_FILE"

            # Set hostname if specified
            hostname=$(grep -E '^hostname:' "$CONFIG_FILE" | head -1 | sed 's/^hostname:[[:space:]]*//' | tr -d '"' | tr -d "'" | tr -d '[:space:]')
            if [[ -n "$hostname" ]]; then
              scutil --set HostName "$hostname"
              scutil --set LocalHostName "$hostname"
              scutil --set ComputerName "$hostname"
              log "Set hostname to: $hostname"
            fi

            # Execute bootcmd commands if present
            if grep -q "^bootcmd:" "$CONFIG_FILE"; then
              log "Executing bootcmd commands..."
              awk '/^bootcmd:/{found=1; next} found && /^  - /{gsub(/^  - /, ""); print}' "$CONFIG_FILE" | while read -r cmd; do
                if [[ -n "$cmd" ]]; then
                  log "Running bootcmd: $cmd"
                  eval "$cmd" >> "$LOG_FILE" 2>&1 || log "Warning: bootcmd failed: $cmd"
                fi
              done
            fi

            # Execute runcmd commands if present
            if grep -q "^runcmd:" "$CONFIG_FILE"; then
              log "Executing runcmd commands..."
              awk '/^runcmd:/{found=1; next} found && /^  - /{gsub(/^  - /, ""); print}' "$CONFIG_FILE" | while read -r cmd; do
                if [[ -n "$cmd" ]]; then
                  log "Running runcmd: $cmd"
                  eval "$cmd" >> "$LOG_FILE" 2>&1 || log "Warning: runcmd failed: $cmd"
                fi
              done
            fi

            log "Cloud-init configuration applied successfully"
          else
            log "No cloud-init configuration found at $CONFIG_FILE"
          fi
        ''
      ];
      RunAtLoad = true;
      StandardOutPath = "/var/log/cloud-init.stdout";
      StandardErrorPath = "/var/log/cloud-init.stderr";
    };
  };

  # Also apply cloud-init on every darwin-rebuild switch
  system.activationScripts.cloud-init = {
    text = ''
      echo "Applying cloud-init configuration during activation..."
      CONFIG_FILE="/etc/cloud-init.yaml"

      if [[ -f "$CONFIG_FILE" ]]; then
        # Set hostname if specified
        hostname=$(grep -E '^hostname:' "$CONFIG_FILE" | head -1 | sed 's/^hostname:[[:space:]]*//' | tr -d '"' | tr -d "'" | tr -d '[:space:]')
        if [[ -n "$hostname" ]]; then
          echo "Setting hostname to: $hostname"
          scutil --set HostName "$hostname"
          scutil --set LocalHostName "$hostname"
          scutil --set ComputerName "$hostname"
        fi

        # Execute bootcmd commands if present
        if grep -q "^bootcmd:" "$CONFIG_FILE"; then
          echo "Executing bootcmd commands..."
          awk '/^bootcmd:/{found=1; next} found && /^  - /{gsub(/^  - /, ""); print}' "$CONFIG_FILE" | while read -r cmd; do
            if [[ -n "$cmd" ]]; then
              echo "Running bootcmd: $cmd"
              eval "$cmd" || echo "Warning: bootcmd failed: $cmd"
            fi
          done
        fi

        # Execute runcmd commands if present (only on first boot or explicitly requested)
        # Note: runcmd is typically for first-boot only, so we skip it during activation
        # to avoid re-running potentially destructive commands

        echo "Cloud-init configuration applied during activation"
      else
        echo "No cloud-init configuration found at $CONFIG_FILE"
      fi
    '';
  };
}
