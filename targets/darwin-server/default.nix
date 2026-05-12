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
            # Auth token will be auto-generated on first run
            # CLI can connect using: export OPENCLAW_GATEWAY_TOKEN=$(jq -r '.gateway.auth.token' ~/.openclaw-wadsworth/openclaw.json)
          };

          # Secrets provider configuration
          secrets = {
            providers = {
              file = {
                source = "file";
                path = "/Users/monkey/.config/openclaw/secrets.json";
                mode = "json";
              };
            };
            defaults = {
              file = "file";
            };
          };

          # Discord channel config using SecretRef
          channels.discord = {
            token = {
              source = "file";
              provider = "file";
              id = "/discord/token";
            };
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
    # Writes token to a file that gets formatted into JSON for OpenClaw
    programs.onepassword-secrets = {
      enable = true;
      tokenFile = "/Users/monkey/.config/opnix/token";
      secrets = {
        # Write raw token first, then activation script creates JSON
        openclawDiscordToken = {
          reference = "op://openclaw/Wadsworth - Discord API Token/credential";
          path = ".config/openclaw/secrets/discord-token-raw";
          mode = "0600";
        };
      };
    };

    # Activation script to create JSON secrets file for OpenClaw SecretRef
    # This runs on every activation to ensure secrets.json is up to date
    home.activation.createOpenclawSecretsJson = lib.mkForce ''
      TOKEN_FILE="/Users/monkey/.config/openclaw/secrets/discord-token-raw"
      SECRETS_JSON="/Users/monkey/.config/openclaw/secrets.json"

      # Check if token file exists (created by 1Password/opnix)
      if [[ -f "$TOKEN_FILE" ]]; then
        TOKEN=$(cat "$TOKEN_FILE")
        # Create/update JSON secrets file
        echo '{"discord":{"token":"'"$TOKEN"'"}}' > "$SECRETS_JSON"
        chmod 600 "$SECRETS_JSON"
        echo "OpenClaw secrets.json created/updated"
      else
        echo "Note: Discord token file not found (1Password not configured). Run: op signin && opnix sync"
      fi
    '';

    # Activation script to fix OpenClaw plugin dependencies
    # This runs on EVERY activation to ensure symlinks exist
    home.activation.fixOpenclawDeps = lib.mkForce ''

      # Workaround for nix-openclaw Discord plugin missing 'openclaw' package
      # See yak: openclaw-discord-missing-dependency
      PLUGIN_DEPS_DIR="/Users/monkey/.openclaw-wadsworth/plugin-runtime-deps"
      OPENCLAW_PKG="${pkgs.openclaw}/lib/openclaw"

      # Function to create symlinks in all plugin runtime deps directories
      create_openclaw_symlinks() {
        if [[ -d "$PLUGIN_DEPS_DIR" ]]; then
          for dir in "$PLUGIN_DEPS_DIR"/openclaw-*/; do
            if [[ -d "$dir/node_modules" ]]; then
              if [[ ! -e "$dir/node_modules/openclaw" ]]; then
                if [[ -d "$OPENCLAW_PKG" ]]; then
                  ln -sf "$OPENCLAW_PKG" "$dir/node_modules/openclaw"
                  echo "Created symlink for openclaw package in: $dir"
                fi
              fi
            fi
          done
        fi
      }

      # Create symlinks now
      create_openclaw_symlinks

      # Also create a background script that will create symlinks after OpenClaw starts
      # This handles the case where OpenClaw creates new plugin runtime deps directories
      (sleep 10 && create_openclaw_symlinks) &
    '';

    # Create a script that can be run to fix OpenClaw plugin dependencies
    home.file.".local/bin/fix-openclaw-deps" = {
      executable = true;
      text = ''
        #!/bin/bash
        # Fix missing 'openclaw' package in plugin runtime deps
        # Run this if Discord channel fails to start

        PLUGIN_DEPS_DIR="/Users/monkey/.openclaw-wadsworth/plugin-runtime-deps"
        OPENCLAW_PKG="${pkgs.openclaw}/lib/openclaw"

        if [[ -d "$PLUGIN_DEPS_DIR" ]]; then
          for dir in "$PLUGIN_DEPS_DIR"/openclaw-*/; do
            if [[ -d "$dir/node_modules" ]]; then
              if [[ ! -e "$dir/node_modules/openclaw" ]]; then
                if [[ -d "$OPENCLAW_PKG" ]]; then
                  ln -sf "$OPENCLAW_PKG" "$dir/node_modules/openclaw"
                  echo "Created symlink in: $dir"
                fi
              fi
            fi
          done
        fi

        echo "OpenClaw plugin dependencies fixed. Restart the service with:"
        echo "  launchctl kickstart -k gui/$(id - u)/com.steipete.openclaw.gateway.wadsworth"
      '';
    };
  };

  # Enable SSH server for remote access
  # Note: SSH agent forwarding is enabled by default on macOS
  services.openssh.enable = true;

  # Add MegamanX SSH key for passwordless login
  users.users.monkey.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIIxGvpCUmx1UV3K22/+sWLdRknZmlTmQgckoAUCApF8 monkey@MegamanX"
  ];

  # Shell alias for OpenClaw gateway authentication
  # Usage: eval $(openclaw-auth) or add to .zshrc
  environment.shellAliases = {
    openclaw-auth = ''export OPENCLAW_GATEWAY_TOKEN=$(jq -r '.gateway.auth.token' ~/.openclaw-wadsworth/openclaw.json 2>/dev/null || echo "")'';
    openclaw-deploy = ''sudo darwin-rebuild switch --flake github:funkymonkeymonk/nix/feat/openclaw-nix-module#darwin-server --impure --refresh'';
    openclaw-restart = ''launchctl kickstart -k gui/$(id - u)/com.steipete.openclaw.gateway.wadsworth'';
    openclaw-logs = ''tail -f /var/folders/*/T/openclaw-*/openclaw-*.log'';
  };

  # OpenClaw plugin dependency fix - runs before OpenClaw starts
  # This ensures the 'openclaw' package symlink exists in plugin runtime deps
  launchd.agents.fix-openclaw-deps = {
    serviceConfig = {
      Label = "com.funkymonkeymonk.fix-openclaw-deps";
      ProgramArguments = [
        "${pkgs.bash}/bin/bash"
        "-c"
        ''
          PLUGIN_DEPS_DIR="/Users/monkey/.openclaw-wadsworth/plugin-runtime-deps"
          OPENCLAW_PKG="${pkgs.openclaw}/lib/openclaw"

          # Keep checking and creating symlinks every 5 seconds
          while true; do
            if [[ -d "$PLUGIN_DEPS_DIR" ]]; then
              for dir in "$PLUGIN_DEPS_DIR"/openclaw-*/; do
                if [[ -d "$dir/node_modules" && ! -e "$dir/node_modules/openclaw" ]]; then
                  ln -sf "$OPENCLAW_PKG" "$dir/node_modules/openclaw"
                  logger "Created openclaw symlink in: $dir"
                fi
              done
            fi
            sleep 5
          done
        ''
      ];
      RunAtLoad = true;
      KeepAlive = true;
      StandardOutPath = "/tmp/fix-openclaw-deps.log";
      StandardErrorPath = "/tmp/fix-openclaw-deps.log";
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
