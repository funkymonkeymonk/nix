# darwin-server target configuration
# Headless Darwin (macOS) server for macOS VM management via Lume
# Hardware: Mac M4 with 24GB RAM
# Primary User: monkey (admin)
{
  mkUser,
  inputs,
  pkgs,
  lib,
  ...
}: {
  nixpkgs.hostPlatform = "aarch64-darwin";
  nixpkgs.config.permittedInsecurePackages = [
    "openclaw-2026.4.22"
  ];
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
        # Local Ollama is now available, but user can still select
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
      # Enable Ollama with Qwen 7B for wadsworth
      ollama = {
        enable = true;
        acceleration = "metal"; # Use Apple Silicon GPU
        models = ["qwen2.5:7b"];
      };
    };

  # Enable OpenClaw via official nix-openclaw home-manager module
  # The module is loaded via homeManagerModules.openclaw in flake.nix
  # Note: Darwin uses home-manager module, NixOS uses system module
  home-manager.users.monkey = {
    programs.openclaw = {
      enable = true;

      # Documents directory with wadsworth's personality and instructions
      documents = ./documents;

      # Wadsworth instance - personal AI assistant
      instances.wadsworth = {
        enable = true;
        gatewayPort = 18789;

        config = {
          gateway = {
            mode = "local";
          };

          # Discord channel config
          # Token is injected via environment variable at runtime
          channels.discord = {
            allowFrom = ["279110923438915586"];
            dmPolicy = "pairing";
          };

          agents = {
            defaults = {
              # Use local Ollama with Qwen 7B
              model = "ollama/qwen2.5:7b";
            };
          };
        };

        # Environment for Ollama connection
        environment = {
          OLLAMA_HOST = "127.0.0.1:11434";
        };
      };
    };

    # 1Password secrets for wadsworth (Discord bot token)
    programs.onepassword-secrets = {
      enable = true;
      tokenFile = "/Users/monkey/.config/opnix/token";
      secrets = {
        openclawDiscordToken = {
          reference = "op://openclaw/Wadsworth - Discord API Token/credential";
          path = ".config/openclaw/secrets/discord-bot-token";
          mode = "0600";
        };
      };
    };

    # Activation script to inject Discord token into OpenClaw config
    home.activation.injectDiscordToken = lib.hm.dag.entryAfter ["writeBoundary"] ''
      TOKEN_FILE="/Users/monkey/.config/openclaw/secrets/discord-bot-token"
      CONFIG_FILE="/Users/monkey/.openclaw-wadsworth/openclaw.json"

      # Wait for token file to exist (1Password may still be syncing)
      for i in {1..30}; do
        if [[ -f "$TOKEN_FILE" ]]; then
          break
        fi
        echo "Waiting for Discord token file..."
        sleep 1
      done

      if [[ -f "$TOKEN_FILE" && -f "$CONFIG_FILE" ]]; then
        TOKEN=$(cat "$TOKEN_FILE")
        TMP_CONFIG=$(mktemp)
        ${pkgs.jq}/bin/jq --arg token "$TOKEN" '.channels.discord.token = $token' "$CONFIG_FILE" > "$TMP_CONFIG"
        mv "$TMP_CONFIG" "$CONFIG_FILE"
        chmod 600 "$CONFIG_FILE"
        echo "Discord token injected into OpenClaw config"
      else
        echo "Warning: Could not inject Discord token - file not found"
        echo "  Token file: $TOKEN_FILE"
        echo "  Config file: $CONFIG_FILE"
      fi
    '';
  };

  # Enable SSH server for remote access
  # Note: SSH agent forwarding is enabled by default on macOS
  services.openssh.enable = true;

  # Add MegamanX SSH key for passwordless login
  users.users.monkey.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIIxGvpCUmx1UV3K22/+sWLdRknZmlTmQgckoAUCApF8 monkey@MegamanX"
  ];

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
