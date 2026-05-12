# Vane service module for Darwin (macOS)
#
# Uses launchd user agents to manage Vane Docker containers.
# Creates and manages a dedicated Colima VM for isolation.
# Users control the service via standard launchctl commands.
{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.myConfig.vane;

  # Common values are exposed via config._vaneCommon from common.nix
  inherit
    (config._vaneCommon)
    vaneStartScript
    dockerComposeYaml
    hasOpnixBaseUrl
    openaiBaseUrlSecretPath
    ;

  # Get the primary user for launchd environment
  primaryUser =
    if config.myConfig.users != []
    then (builtins.head config.myConfig.users).name
    else "root";

  # Darwin home directory
  darwinHomeDir = "/Users/${primaryUser}";

  # Colima VM configuration for Vane
  colimaProfile = "vane";
  colimaSocket = "${darwinHomeDir}/.colima/vane/docker.sock";

  # Script to ensure Colima VM is running
  vaneColimaScript = pkgs.writeShellScriptBin "vane-colima" ''
    set -euo pipefail

    # Ensure colima and docker are in PATH
    export PATH="${pkgs.colima}/bin:${pkgs.docker}/bin:$PATH"

    COMMAND=''${1:-status}

    case "$COMMAND" in
      start)
        if colima list | grep -q "^${colimaProfile}"; then
          if colima list | grep "^${colimaProfile}" | grep -q "Running"; then
            echo "Vane Colima VM is already running"
            exit 0
          else
            echo "Starting existing Vane Colima VM..."
            colima start ${colimaProfile}
          fi
        else
          echo "Creating Vane Colima VM (one-time setup)..."
          echo "This will create a dedicated Docker VM for Vane with:"
          echo "  CPU: ${toString cfg.colima.cpu} cores"
          echo "  Memory: ${toString cfg.colima.memory}GB"
          echo "  Disk: ${toString cfg.colima.disk}GB"
          colima start ${colimaProfile} \
            --cpu ${toString cfg.colima.cpu} \
            --memory ${toString cfg.colima.memory} \
            --disk ${toString cfg.colima.disk} \
            --vm-type vz \
            --mount-type virtiofs
        fi
        ;;
      stop)
        if colima list | grep "^${colimaProfile}" | grep -q "Running"; then
          echo "Stopping Vane Colima VM..."
          colima stop ${colimaProfile}
        fi
        ;;
      status)
        if colima list | grep -q "^${colimaProfile}"; then
          colima list | grep "^${colimaProfile}"
        else
          echo "Vane Colima VM does not exist"
        fi
        ;;
      delete)
        echo "Deleting Vane Colima VM..."
        colima delete ${colimaProfile} || true
        ;;
      *)
        echo "Vane Colima Manager"
        echo ""
        echo "Usage: vane-colima {start|stop|status|delete}"
        echo ""
        echo "Commands:"
        echo "  start   - Start/create the Vane Colima VM"
        echo "  stop    - Stop the Vane Colima VM"
        echo "  status  - Show VM status"
        echo "  delete  - Delete the VM (data will be lost)"
        ;;
    esac
  '';

  # Default model for Vane (configurable via options)
  inherit (cfg) defaultModel embeddingModel;

  # Script to pull required models
  pullModelsScript = pkgs.writeShellScript "vane-pull-models" ''
    set -euo pipefail

    export HOME="${darwinHomeDir}"
    # Add common Ollama installation paths including nix-darwin paths
    export PATH="/run/current-system/sw/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$HOME/.nix-profile/bin:/nix/var/nix/profiles/default/bin:$PATH"

    # Check if ollama is available on the host
    if ! command -v ollama > /dev/null 2>&1; then
      echo "[vane] WARNING: Ollama not found in PATH. Please install Ollama manually."
      echo "[vane] Checked paths: /run/current-system/sw/bin, /opt/homebrew/bin, /usr/local/bin"
      exit 0
    fi

    ${lib.optionalString (defaultModel != null) ''
      # Pull chat model
      if ollama list | grep -q "${defaultModel}"; then
        echo "[vane] Chat model ${defaultModel} is already installed"
      else
        echo "[vane] Pulling ${defaultModel} chat model for Vane (this may take several minutes)..."
        ollama pull ${defaultModel}
        echo "[vane] Successfully pulled ${defaultModel}"
      fi
    ''}

    ${lib.optionalString (embeddingModel != null) ''
      # Pull embedding model
      if ollama list | grep -q "${embeddingModel}"; then
        echo "[vane] Embedding model ${embeddingModel} is already installed"
      else
        echo "[vane] Pulling ${embeddingModel} embedding model for Vane..."
        ollama pull ${embeddingModel}
        echo "[vane] Successfully pulled ${embeddingModel}"
      fi
    ''}
  '';

  # Script to create Vane config with configured models
  # Uses marker file pattern: only configures once, but can be reset
  createVaneConfigScript = pkgs.writeShellScript "vane-create-config" ''
    set -euo pipefail

    DATA_DIR="${cfg.dataDir}"
    CONFIG_FILE="$DATA_DIR/vane/config.json"
    NIX_MARKER="$DATA_DIR/vane/.nix-configured"

    # Create the config directory if it doesn't exist
    mkdir -p "$DATA_DIR/vane"

    # Only create config if Nix hasn't configured it yet
    # Remove $NIX_MARKER to force re-configuration
    if [ -f "$NIX_MARKER" ]; then
      echo "[vane] Already configured by Nix, skipping auto-configuration"
      echo "[vane] Remove $NIX_MARKER to force re-configuration"
      exit 0
    fi

    ${lib.optionalString (defaultModel != null) ''
      # Create the config.json with configured models
      cat > "$CONFIG_FILE" << 'VANECONFIG'
      {
        "version": 1,
        "setupComplete": true,
        "preferences": {
          "theme": "dark"
        },
        "personalization": {},
        "modelProviders": [
          {
            "id": "ollama-local",
            "name": "Ollama Local",
            "type": "ollama",
            "chatModels": [
              {
                "name": "${defaultModel}",
                "key": "${defaultModel}"
              }
            ],
            "embeddingModels": [
              ${lib.optionalString (embeddingModel != null) ''        {
                      "name": "${embeddingModel}",
                      "key": "${embeddingModel}"
                    }''}
            ],
            "config": {
              "baseURL": "${cfg.ollamaUrl}"
            },
            "hash": "ollama-local-nix"
          }
        ],
        "search": {
          "searxngURL": "${cfg.searxngUrl}"
        }
      }
      VANECONFIG

      echo "[vane] Created config.json with chat model: ${defaultModel}"
      ${lib.optionalString (embeddingModel != null) ''echo "[vane] Embedding model: ${embeddingModel}"''}

      # Mark as configured by Nix
      touch "$NIX_MARKER"
      echo "[vane] Configuration complete. Remove $NIX_MARKER to re-configure."
    ''}

    ${lib.optionalString (defaultModel == null) ''
      echo "[vane] No default model configured, Vane will prompt for setup on first access"
      # Still mark as configured so we don't keep checking
      touch "$NIX_MARKER"
    ''}
  '';

  # Script to fix SSH port forwarding for Colima VM
  # This addresses a known issue where vz (Apple Virtualization) SSH port forwarding fails during startup
  vanePortForwardScript = pkgs.writeShellScriptBin "vane-fix-port-forwarding" ''
    set -euo pipefail

    export PATH="${pkgs.openssh}/bin:$PATH"

    LIMA_HOME="${darwinHomeDir}/.colima/_lima"
    SSH_SOCK="''${LIMA_HOME}/colima-${colimaProfile}/ssh.sock"
    COLIMA_SSH_PORT=49643  # Default SSH port for colima-vane

    # Function to add port forwarding via SSH control master
    add_port_forward() {
      local port=$1
      if ! lsof -i :"$port" > /dev/null 2>&1; then
        echo "[vane] Adding port forwarding for port $port..."
        ssh -F /dev/null \
          -o IdentityFile="''${LIMA_HOME}/_config/user" \
          -o StrictHostKeyChecking=no \
          -o UserKnownHostsFile=/dev/null \
          -o NoHostAuthenticationForLocalhost=yes \
          -o PreferredAuthentications=publickey \
          -o Compression=no \
          -o BatchMode=yes \
          -o IdentitiesOnly=yes \
          -o GSSAPIAuthentication=no \
          -o "Ciphers=^aes128-gcm@openssh.com,aes256-gcm@openssh.com" \
          -o ControlMaster=auto \
          -o "ControlPath=''${SSH_SOCK}" \
          -o ControlPersist=yes \
          -T -O forward -L "0.0.0.0:$port:[::]:$port" \
          -N -f -p $COLIMA_SSH_PORT 127.0.0.1 2>/dev/null || true
      fi
    }

    # Check if Colima VM is running
    if [ ! -S "''${SSH_SOCK}" ]; then
      echo "[vane] Colima VM SSH socket not found, skipping port forwarding fix"
      exit 0
    fi

    # Add port forwarding for Vane (3000) and other common ports
    add_port_forward 3000
    add_port_forward 8080
    add_port_forward 11434  # Ollama
    add_port_forward 9000   # MinIO
    add_port_forward 9001   # MinIO console

    echo "[vane] Port forwarding check complete"
  '';

  # Launchd service script
  vaneServiceScript = pkgs.writeShellScript "vane-launchd-service" ''
    set -euo pipefail

    export HOME="${darwinHomeDir}"
    export USER="${primaryUser}"
    export PATH="${pkgs.colima}/bin:${pkgs.docker}/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin"

    ${lib.optionalString hasOpnixBaseUrl ''
      # Read OpenAI base URL from opnix-managed secret file
      OPENAI_BASE_URL_FILE="$HOME/${openaiBaseUrlSecretPath}"
      if [[ -f "$OPENAI_BASE_URL_FILE" ]]; then
        export OPENAI_BASE_URL
        OPENAI_BASE_URL=$(cat "$OPENAI_BASE_URL_FILE")
        echo "[vane] Loaded OpenAI base URL from secret file"
      else
        echo "[vane] WARNING: openaiBaseUrlOpnixItem is set but secret file not found at $OPENAI_BASE_URL_FILE"
        echo "[vane] Ensure opnix has run and the 1Password item exists"
      fi
    ''}

    # Pull configured models first
    echo "[vane] Checking/installing configured models..."
    ${pullModelsScript}

    # Create Vane config with configured models
    ${createVaneConfigScript}

    # Start Colima VM for Vane
    echo "[vane] Ensuring Colima VM is running..."
    ${vaneColimaScript}/bin/vane-colima start

    # Wait for Docker socket to be available
    MAX_RETRIES=30
    RETRY_COUNT=0
    while [ ! -S "${colimaSocket}" ]; do
      RETRY_COUNT=$((RETRY_COUNT + 1))
      if [ $RETRY_COUNT -ge $MAX_RETRIES ]; then
        echo "[vane] ERROR: Docker socket not available after $MAX_RETRIES attempts"
        exit 1
      fi
      sleep 2
    done

    # Set Docker to use Vane's Colima VM
    export DOCKER_HOST="unix://${colimaSocket}"

    echo "[vane] Starting Vane containers..."
    ${vaneStartScript}

    # Fix SSH port forwarding (workaround for vz issue)
    echo "[vane] Ensuring port forwarding is working..."
    sleep 5  # Give containers time to start
    ${vanePortForwardScript}/bin/vane-fix-port-forwarding || true
  '';
in {
  imports = [./common.nix];

  config = mkIf cfg.enable {
    # Install helper scripts and dependencies (including Caddy for reverse proxy)
    environment.systemPackages = [
      vaneColimaScript
      vanePortForwardScript
      pkgs.colima
      pkgs.docker
      pkgs.docker-compose
      pkgs.caddy
      pkgs.openssh
      pkgs.lsof
    ];

    # Shell aliases for service management
    environment.shellAliases = {
      # Service control via launchctl
      "vane.start" = "launchctl start com.vane.service";
      "vane.stop" = "launchctl stop com.vane.service";
      "vane.restart" = "launchctl stop com.vane.service 2>/dev/null; sleep 2; launchctl start com.vane.service";
      "vane.status" = "launchctl list com.vane.service 2>/dev/null | tail -1 || echo 'Vane service: not running'";

      # Colima VM management
      "vane.vm.start" = "vane-colima start";
      "vane.vm.stop" = "vane-colima stop";
      "vane.vm.status" = "vane-colima status";

      # Logs (launchd user agents log to /tmp)
      "vane.logs" = "tail -f /tmp/vane.log 2>/dev/null || echo 'No logs yet'";
      "vane.errors" = "tail -f /tmp/vane.error.log 2>/dev/null || echo 'No error logs'";

      # Reset config to Nix defaults
      "vane.reset-config" = "rm -f ${cfg.dataDir}/vane/.nix-configured && rm -f ${cfg.dataDir}/vane/config.json && echo 'Config reset. Run vane.restart to apply.'";

      # Docker commands (use Vane's Colima context)
      "vane.docker" = "DOCKER_HOST=unix://${colimaSocket} docker";
      "vane.ps" = "DOCKER_HOST=unix://${colimaSocket} docker-compose -f ${dockerComposeYaml} ps";

      # Port forwarding fix (workaround for vz SSH port forwarding issues)
      "vane.fix-ports" = "vane-fix-port-forwarding";
    };

    # Create launchd user agent for Vane
    launchd.user.agents.vane = {
      serviceConfig = {
        Label = "com.vane.service";
        ProgramArguments = ["${vaneServiceScript}"];
        RunAtLoad = cfg.autoStart;
        KeepAlive = true;
        StandardOutPath = "/tmp/vane.log";
        StandardErrorPath = "/tmp/vane.error.log";
      };
    };

    # Caddy reverse proxy configuration
    launchd.user.agents.vane-proxy = {
      serviceConfig = {
        Label = "com.vane.proxy";
        ProgramArguments = [
          "${pkgs.caddy}/bin/caddy"
          "reverse-proxy"
          "--from"
          "vane.localhost:80"
          "--to"
          "127.0.0.1:${toString cfg.port}"
        ];
        RunAtLoad = true;
        KeepAlive = true;
        StandardOutPath = "/tmp/vane-proxy.log";
        StandardErrorPath = "/tmp/vane-proxy.error.log";
      };
    };

    # Ensure data directory exists and configure hosts
    system.activationScripts.postActivation.text = lib.mkAfter ''
      echo "Setting up Vane data directory..."
      mkdir -p "${cfg.dataDir}/logs"
      mkdir -p "${cfg.dataDir}/vane"
      mkdir -p "${cfg.dataDir}/searxng"
      chown -R ${primaryUser} "${cfg.dataDir}" 2>/dev/null || true

      # Add vane.localhost to /etc/hosts if not present
      if ! grep -q "vane.localhost" /etc/hosts 2>/dev/null; then
        echo "Adding vane.localhost to /etc/hosts..."
        echo "127.0.0.1 vane.localhost # Vane AI search engine" >> /etc/hosts
      fi

      echo "Vane will be accessible at: http://vane.localhost"
    '';
  };
}
