# darwin-server — headless macOS server for VM hosting
# Hardware: Mac M4 with 24GB RAM
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
      opencode.model = null;
      lume = {
        enable = true;
        enableBackgroundService = true;
        port = 7777;
        enableAutoUpdater = true;
        prePullImages = ["macos-tahoe-vanilla:latest"];
      };
    };

  # Add MegamanX SSH key for passwordless login
  users.users.monkey.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIIxGvpCUmx1UV3K22/+sWLdRknZmlTmQgckoAUCApF8 monkey@MegamanX"
  ];

  # Allow passwordless sudo for deploy-rs automated deployments
  security.sudo.extraConfig = lib.mkForce ''
    Defaults timestamp_timeout=0
    monkey ALL=(ALL) NOPASSWD: ALL
  '';

  # OpenClaw wadsworth configuration
  home-manager.users.monkey.programs.openclaw = {
    enable = true;
    documents = ./documents;
    instances.wadsworth = {
      enable = true;
      gatewayPort = 18789;
      config = {
        gateway = {
          mode = "local";
          bind = "lan";
        };
        secrets = {
          providers = {
            file = {
              source = "file";
              path = "/Users/monkey/.config/openclaw/secrets.json";
              mode = "json";
            };
          };
          defaults = {file = "file";};
        };
        channels.discord = {
          token = {
            source = "file";
            provider = "file";
            id = "/discord/token";
          };
          allowFrom = ["279110923438915586"];
          dmPolicy = "pairing";
        };
        agents.defaults = {
          model = "ollama/qwen3:14b";
        };
      };
      environment = {
        OLLAMA_HOST = "127.0.0.1:11434";
        OLLAMA_API_KEY = "ollama-local";
      };
    };
  };

  # 1Password secrets for wadsworth
  home-manager.users.monkey.programs.onepassword-secrets = {
    enable = true;
    tokenFile = "/Users/monkey/.config/opnix/token";
    secrets = {
      openclawDiscordToken = {
        reference = "op://openclaw/Wadsworth - Discord API Token/credential";
        path = ".config/openclaw/secrets/discord-token-raw";
        mode = "0600";
      };
    };
  };

  # Activation script to create JSON secrets file for OpenClaw
  home-manager.users.monkey.home.activation.createOpenclawSecretsJson = lib.mkForce ''
    TOKEN_FILE="/Users/monkey/.config/openclaw/secrets/discord-token-raw"
    SECRETS_JSON="/Users/monkey/.config/openclaw/secrets.json"
    if [[ -f "$TOKEN_FILE" ]]; then
      TOKEN=$(cat "$TOKEN_FILE")
      echo '{"discord":{"token":"'"$TOKEN"'"}}' > "$SECRETS_JSON"
      chmod 600 "$SECRETS_JSON"
      echo "OpenClaw secrets.json created/updated"
    else
      echo "Note: Discord token file not found (1Password not configured). Run: op signin && opnix sync"
    fi
  '';

  # Activation script to fix OpenClaw plugin dependencies
  home-manager.users.monkey.home.activation.fixOpenclawDeps = lib.mkForce ''
    PLUGIN_DEPS_DIR="/Users/monkey/.openclaw-wadsworth/plugin-runtime-deps"
    OPENCLAW_PKG="${pkgs.openclaw}/lib/openclaw"
    create_openclaw_symlinks() {
      if [[ -d "$PLUGIN_DEPS_DIR" ]]; then
        for dir in "$PLUGIN_DEPS_DIR"/openclaw-*/; do
          if [[ -d "$dir/node_modules" ]] && [[ ! -e "$dir/node_modules/openclaw" ]]; then
            if [[ -d "$OPENCLAW_PKG" ]]; then
              ln -sf "$OPENCLAW_PKG" "$dir/node_modules/openclaw"
              echo "Created symlink for openclaw package in: $dir"
            fi
          fi
        done
      fi
    }
    create_openclaw_symlinks
    (sleep 10 && create_openclaw_symlinks) &
  '';

  # Fix openclaw script
  home-manager.users.monkey.home.file.".local/bin/fix-openclaw-deps" = {
    executable = true;
    text = ''
      #!/bin/bash
      PLUGIN_DEPS_DIR="/Users/monkey/.openclaw-wadsworth/plugin-runtime-deps"
      OPENCLAW_PKG="${pkgs.openclaw}/lib/openclaw"
      if [[ -d "$PLUGIN_DEPS_DIR" ]]; then
        for dir in "$PLUGIN_DEPS_DIR"/openclaw-*/; do
          if [[ -d "$dir/node_modules" ]] && [[ ! -e "$dir/node_modules/openclaw" ]]; then
            if [[ -d "$OPENCLAW_PKG" ]]; then
              ln -sf "$OPENCLAW_PKG" "$dir/node_modules/openclaw"
              echo "Created symlink in: $dir"
            fi
          fi
        done
      fi
      echo "OpenClaw plugin dependencies fixed. Restart the service with:"
      echo "  launchctl kickstart -k gui/$(id -u)/com.steipete.openclaw.gateway.wadsworth"
    '';
  };

  home-manager.users.monkey.home.file.".local/bin/fix-openclaw-plist" = {
    executable = true;
    text = ''
      #!/bin/bash
      PLIST="$HOME/Library/LaunchAgents/com.steipete.openclaw.gateway.wadsworth.plist"
      LOG_DIR="$HOME/.openclaw-wadsworth/logs"
      if [[ ! -f "$PLIST" ]]; then
        echo "Error: Plist not found at $PLIST"
        exit 1
      fi
      mkdir -p "$LOG_DIR"
      chmod 644 "$PLIST" 2>/dev/null || true
      /usr/libexec/PlistBuddy -c "Set :StandardOutPath $LOG_DIR/openclaw-gateway-wadsworth.log" "$PLIST" 2>/dev/null || \
        /usr/libexec/PlistBuddy -c "Add :StandardOutPath string $LOG_DIR/openclaw-gateway-wadsworth.log" "$PLIST"
      /usr/libexec/PlistBuddy -c "Set :StandardErrorPath $LOG_DIR/openclaw-gateway-wadsworth.log" "$PLIST" 2>/dev/null || \
        /usr/libexec/PlistBuddy -c "Add :StandardErrorPath string $LOG_DIR/openclaw-gateway-wadsworth.log" "$PLIST"
      PROGRAM_ARGS="/nix/store/in4yc03diyvs2n2wgf3nva4hbvml8v1j-bash-interactive-5.3p9/bin/bash"
      /usr/libexec/PlistBuddy -c "Set :ProgramArguments:0 $PROGRAM_ARGS" "$PLIST"
      echo "OpenClaw plist fixed. Reload: launchctl unload $PLIST && launchctl load $PLIST"
    '';
  };

  home-manager.users.monkey.home.activation.fixOpenclawPlist = lib.mkForce ''
    export PATH="/usr/bin:/bin:$PATH"
    PLIST="/Users/monkey/Library/LaunchAgents/com.steipete.openclaw.gateway.wadsworth.plist"
    LOG_DIR="/Users/monkey/.openclaw-wadsworth/logs"
    NEEDS_RESTART=false
    if [[ -f "$PLIST" ]]; then
      mkdir -p "$LOG_DIR"
      chmod 644 "$PLIST" 2>/dev/null || true
      /usr/libexec/PlistBuddy -c "Set :StandardOutPath /Users/monkey/.openclaw-wadsworth/logs/openclaw-gateway-wadsworth.log" "$PLIST" 2>/dev/null || true
      /usr/libexec/PlistBuddy -c "Set :StandardErrorPath /Users/monkey/.openclaw-wadsworth/logs/openclaw-gateway-wadsworth.log" "$PLIST" 2>/dev/null || true
      /usr/libexec/PlistBuddy -c "Set :ProgramArguments:0 /nix/store/in4yc03diyvs2n2wgf3nva4hbvml8v1j-bash-interactive-5.3p9/bin/bash" "$PLIST" 2>/dev/null || true
      CURRENT_CMD=$(/usr/libexec/PlistBuddy -c "Print :ProgramArguments:2" "$PLIST" 2>/dev/null || echo "")
      if [[ -n "$CURRENT_CMD" ]] && [[ "$CURRENT_CMD" != *"--host"* ]]; then
        FIXED_CMD=$(echo "$CURRENT_CMD" | sed 's/gateway --port/gateway --host 0.0.0.0 --port/')
        /usr/libexec/PlistBuddy -c "Set :ProgramArguments:2 $FIXED_CMD" "$PLIST" 2>/dev/null || true
        echo "OpenClaw gateway bind fixed: added --host 0.0.0.0"
        NEEDS_RESTART=true
      fi
      chmod 444 "$PLIST" 2>/dev/null || true
      if [[ "$NEEDS_RESTART" == "true" ]]; then
        if launchctl list | grep -q "com.steipete.openclaw.gateway.wadsworth"; then
          launchctl unload "$PLIST" 2>/dev/null || true
          sleep 1
          launchctl load "$PLIST" 2>/dev/null || true
          echo "OpenClaw gateway restarted"
        fi
      fi
    fi
  '';

  # Background fix-openclaw-deps daemon
  launchd.agents.fix-openclaw-deps = {
    serviceConfig = {
      Label = "com.funkymonkeymonk.fix-openclaw-deps";
      ProgramArguments = [
        "${pkgs.bash}/bin/bash"
        "-c"
        ''
          PLUGIN_DEPS_DIR="/Users/monkey/.openclaw-wadsworth/plugin-runtime-deps"
          OPENCLAW_PKG="${pkgs.openclaw}/lib/openclaw"
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

  # Cloud-init support
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
          log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $1" | tee -a "$LOG_FILE"; }
          if [[ -f "$CONFIG_FILE" ]]; then
            log "Applying cloud-init configuration from $CONFIG_FILE"
            hostname=$(grep -E '^hostname:' "$CONFIG_FILE" | head -1 | sed 's/^hostname:[[:space:]]*//' | tr -d '"' | tr -d "'" | tr -d '[:space:]')
            if [[ -n "$hostname" ]]; then
              scutil --set HostName "$hostname"
              scutil --set LocalHostName "$hostname"
              scutil --set ComputerName "$hostname"
              log "Set hostname to: $hostname"
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

  system.activationScripts.cloud-init = {
    text = ''
      echo "Applying cloud-init configuration during activation..."
      CONFIG_FILE="/etc/cloud-init.yaml"
      if [[ -f "$CONFIG_FILE" ]]; then
        hostname=$(grep -E '^hostname:' "$CONFIG_FILE" | head -1 | sed 's/^hostname:[[:space:]]*//' | tr -d '"' | tr -d "'" | tr -d '[:space:]')
        if [[ -n "$hostname" ]]; then
          scutil --set HostName "$hostname"
          scutil --set LocalHostName "$hostname"
          scutil --set ComputerName "$hostname"
        fi
        echo "Cloud-init configuration applied during activation"
      else
        echo "No cloud-init configuration found at $CONFIG_FILE"
      fi
    '';
  };
}
