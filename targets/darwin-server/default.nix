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
    };

  # Enable SSH server for remote access
  services.openssh.enable = true;

  # Add MegamanX SSH key for passwordless login
  users.users.monkey.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIIxGvpCUmx1UV3K22/+sWLdRknZmlTmQgckoAUCApF8 monkey@MegamanX"
  ];

  # Opnix configuration - fetches service account token for MicroVM
  services.onepassword-secrets = {
    enable = true;
    tokenFile = "/etc/opnix-token";
    secrets = {
      openclawServiceAccount = {
        reference = "op://Service Accounts/6p3oex3elzffchzmd2kl3s7cp4/credential";
        path = "/var/lib/opnix/secrets/openclaw-service-account";
        mode = "0600";
      };
    };
  };

  # OpenClaw vfkit MicroVM launchd service
  # Uses opnix-managed token file to start the VM
  launchd.daemons.openclaw-vfkit = {
    serviceConfig = {
      Label = "com.funkymonkey.openclaw-vfkit";
      ProgramArguments = [
        "/bin/sh"
        "-c"
        ''
          set -e
          TOKEN_FILE="/tmp/openclaw-vfkit-opnix-token"
          OPNIX_SECRET="/var/lib/opnix/secrets/openclaw-service-account"
          LOG_DIR="/Users/monkey/Library/Logs"

          mkdir -p "$LOG_DIR"
          mkdir -p "$(dirname "$TOKEN_FILE")"

          # Copy token from opnix-managed location
          echo "$(date '+%Y-%m-%d %H:%M:%S') Setting up opnix token for MicroVM..." >> "$LOG_DIR/openclaw-vfkit.log"
          if [[ -f "$OPNIX_SECRET" ]]; then
            cp "$OPNIX_SECRET" "$TOKEN_FILE"
            chmod 600 "$TOKEN_FILE"
            echo "$(date '+%Y-%m-%d %H:%M:%S') Token file prepared successfully" >> "$LOG_DIR/openclaw-vfkit.log"
          else
            echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: opnix secret not found at $OPNIX_SECRET" >> "$LOG_DIR/openclaw-vfkit.log"
            echo "$(date '+%Y-%m-%d %H:%M:%S') Run 'sudo opnix token set' first to authenticate" >> "$LOG_DIR/openclaw-vfkit.log"
            exit 1
          fi

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
