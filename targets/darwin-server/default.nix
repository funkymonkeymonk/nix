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
  nixpkgs.config.allowInsecurePredicate = attrs: let
    pname = attrs.pname or attrs.name or "";
    fullName = "${pname}-${attrs.version or ""}";
  in
    pname
    == "openclaw"
    || builtins.elem fullName ["olm-3.2.16"];
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
            # Bind to LAN for network access (dashboard available at http://192.168.1.229:18789)
            bind = "lan";
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

    # Create a script to fix the launchd plist (workaround for nix-openclaw wait4path bug)
    home.file.".local/bin/fix-openclaw-plist" = {
      executable = true;
      text = ''
        #!/bin/bash
        # Fix OpenClaw launchd plist (workaround for nix-openclaw wait4path bug)
        # The nix-openclaw module generates incorrect wait4path syntax that causes exit 78

        PLIST="$HOME/Library/LaunchAgents/com.steipete.openclaw.gateway.wadsworth.plist"
        LOG_DIR="$HOME/.openclaw-wadsworth/logs"

        if [[ ! -f "$PLIST" ]]; then
          echo "Error: Plist not found at $PLIST"
          exit 1
        fi

        # Create log directory
        mkdir -p "$LOG_DIR"

        # Make plist writable
        chmod 644 "$PLIST" 2>/dev/null || true

        # Update plist with correct settings
        /usr/libexec/PlistBuddy -c "Set :StandardOutPath $LOG_DIR/openclaw-gateway-wadsworth.log" "$PLIST" 2>/dev/null || \
          /usr/libexec/PlistBuddy -c "Add :StandardOutPath string $LOG_DIR/openclaw-gateway-wadsworth.log" "$PLIST"

        /usr/libexec/PlistBuddy -c "Set :StandardErrorPath $LOG_DIR/openclaw-gateway-wadsworth.log" "$PLIST" 2>/dev/null || \
          /usr/libexec/PlistBuddy -c "Add :StandardErrorPath string $LOG_DIR/openclaw-gateway-wadsworth.log" "$PLIST"

        # Fix the ProgramArguments to use bash from nix instead of /bin/sh for proper wait4path handling
        # The issue is that /bin/sh doesn't handle the wait4path && exec pattern correctly
        PROGRAM_ARGS="/nix/store/in4yc03diyvs2n2wgf3nva4hbvml8v1j-bash-interactive-5.3p9/bin/bash"
        /usr/libexec/PlistBuddy -c "Set :ProgramArguments:0 $PROGRAM_ARGS" "$PLIST"

        echo "OpenClaw plist fixed. Reload the service with:"
        echo "  launchctl unload $PLIST"
        echo "  launchctl load $PLIST"
      '';
    };

    # Activation script to fix the launchd plist after each rebuild
    # This works around the nix-openclaw module bug with wait4path and missing --host flag
    home.activation.fixOpenclawPlist = lib.mkForce ''
      export PATH="/usr/bin:/bin:$PATH"

      PLIST="/Users/monkey/Library/LaunchAgents/com.steipete.openclaw.gateway.wadsworth.plist"
      LOG_DIR="/Users/monkey/.openclaw-wadsworth/logs"
      NEEDS_RESTART=false

      if [[ -f "$PLIST" ]]; then
        # Create log directory
        mkdir -p "$LOG_DIR"

        # Make plist writable and fix it
        chmod 644 "$PLIST" 2>/dev/null || true

        # Fix log paths using PlistBuddy
        /usr/libexec/PlistBuddy -c "Set :StandardOutPath /Users/monkey/.openclaw-wadsworth/logs/openclaw-gateway-wadsworth.log" "$PLIST" 2>/dev/null || true
        /usr/libexec/PlistBuddy -c "Set :StandardErrorPath /Users/monkey/.openclaw-wadsworth/logs/openclaw-gateway-wadsworth.log" "$PLIST" 2>/dev/null || true

        # Fix the shell path to use nix bash for proper wait4path handling
        /usr/libexec/PlistBuddy -c "Set :ProgramArguments:0 /nix/store/in4yc03diyvs2n2wgf3nva4hbvml8v1j-bash-interactive-5.3p9/bin/bash" "$PLIST" 2>/dev/null || true

        # Fix the gateway command to bind to all interfaces (not just localhost)
        # This reads the current ProgramArguments:2 value and adds --host 0.0.0.0 if missing
        CURRENT_CMD=$(/usr/libexec/PlistBuddy -c "Print :ProgramArguments:2" "$PLIST" 2>/dev/null || echo "")
        if [[ -n "$CURRENT_CMD" ]] && [[ "$CURRENT_CMD" != *"--host"* ]]; then
          # Add --host 0.0.0.0 before the port argument
          FIXED_CMD=$(echo "$CURRENT_CMD" | sed 's/gateway --port/gateway --host 0.0.0.0 --port/')
          /usr/libexec/PlistBuddy -c "Set :ProgramArguments:2 $FIXED_CMD" "$PLIST" 2>/dev/null || true
          echo "OpenClaw gateway bind fixed: added --host 0.0.0.0 for network access"
          NEEDS_RESTART=true
        fi

        # Make plist read-only again
        chmod 444 "$PLIST" 2>/dev/null || true

        # Restart the service if we made changes and it's running
        if [[ "$NEEDS_RESTART" == "true" ]]; then
          # Check if service is currently running
          if launchctl list | grep -q "com.steipete.openclaw.gateway.wadsworth"; then
            echo "Restarting OpenClaw gateway to apply changes..."
            launchctl unload "$PLIST" 2>/dev/null || true
            sleep 1
            launchctl load "$PLIST" 2>/dev/null || true
            echo "OpenClaw gateway restarted"
          else
            echo "OpenClaw gateway not running, loading..."
            launchctl load "$PLIST" 2>/dev/null || true
          fi
        fi

        echo "OpenClaw plist fixed (workaround for nix-openclaw bugs)"
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
