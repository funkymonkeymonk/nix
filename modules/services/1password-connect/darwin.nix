# 1Password Connect Server module for Darwin (macOS)
# Runs Connect inside a Colima VM as a system daemon
# https://developer.1password.com/docs/connect
{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.myConfig.onepassword-connect;

  # System-wide paths for daemon operation
  colimaProfile = "connect";
  colimaDataDir = "/var/lib/colima";
  colimaSocket = "${colimaDataDir}/connect/docker.sock";

  # Connect data directory inside Colima VM
  connectDataDir = "/var/lib/1password-connect";

  # Script to manage Colima VM (runs as root)
  connectColimaScript = pkgs.writeShellScriptBin "connect-colima" ''
    set -euo pipefail

    # Ensure colima and docker are in PATH
    export PATH="${pkgs.colima}/bin:${pkgs.docker}/bin:$PATH"
    export LIMA_HOME="${colimaDataDir}/_lima"

    COMMAND=''${1:-status}

    case "$COMMAND" in
      start)
        if colima list | grep -q "^${colimaProfile}"; then
          if colima list | grep "^${colimaProfile}" | grep -q "Running"; then
            echo "Connect Colima VM is already running"
            exit 0
          else
            echo "Starting existing Connect Colima VM..."
            colima start ${colimaProfile}
          fi
        else
          echo "Creating Connect Colima VM (one-time setup)..."
          echo "  CPU: 2 cores"
          echo "  Memory: 2GB"
          echo "  Disk: 10GB"
          mkdir -p ${colimaDataDir}
          colima start ${colimaProfile} \
            --cpu 2 \
            --memory 2 \
            --disk 10 \
            --vm-type vz \
            --mount-type virtiofs
        fi
        ;;
      stop)
        if colima list | grep "^${colimaProfile}" | grep -q "Running"; then
          echo "Stopping Connect Colima VM..."
          colima stop ${colimaProfile}
        fi
        ;;
      status)
        if colima list | grep -q "^${colimaProfile}"; then
          colima list | grep "^${colimaProfile}"
        else
          echo "Connect Colima VM does not exist"
        fi
        ;;
      delete)
        echo "Deleting Connect Colima VM..."
        colima delete ${colimaProfile} || true
        ;;
      shell)
        echo "Opening shell in Connect Colima VM..."
        colima ssh ${colimaProfile}
        ;;
      *)
        echo "Connect Colima Manager"
        echo ""
        echo "Usage: connect-colima {start|stop|status|delete|shell}"
        echo ""
        echo "Commands:"
        echo "  start   - Start/create the Connect Colima VM"
        echo "  stop    - Stop the Connect Colima VM"
        echo "  status  - Show VM status"
        echo "  delete  - Delete the VM (data will be lost)"
        echo "  shell   - Open shell in the VM"
        ;;
    esac
  '';

  # Script to check credentials and start Connect containers
  connectStartScript = pkgs.writeShellScriptBin "connect-start" ''
    set -euo pipefail

    export PATH="${pkgs.colima}/bin:${pkgs.docker}/bin:$PATH"
    export DOCKER_HOST="unix://${colimaSocket}"
    export LIMA_HOME="${colimaDataDir}/_lima"

    CREDENTIALS_FILE="${cfg.credentialsFile}"

    # Wait for Colima to be ready
    echo "Waiting for Colima Docker socket..."
    for i in {1..30}; do
      if [ -S "${colimaSocket}" ]; then
        break
      fi
      if [ $i -eq 30 ]; then
        echo "ERROR: Colima Docker socket not available"
        exit 1
      fi
      sleep 1
    done

    # Check for credentials
    if [ ! -f "$CREDENTIALS_FILE" ]; then
      echo "ERROR: Connect credentials not found at $CREDENTIALS_FILE"
      echo ""
      echo "To set up 1Password Connect:"
      echo "1. Create a Connect server: op connect server create <name>"
      echo "2. Save the credentials file to $CREDENTIALS_FILE"
      echo "3. Restart the service"
      exit 1
    fi

    # Create data directory in Colima VM
    colima ssh ${colimaProfile} -- "sudo mkdir -p ${connectDataDir}/data && sudo chmod 755 ${connectDataDir}"

    # Copy credentials into VM
    echo "Installing credentials..."
    ${pkgs.docker}/bin/docker cp "$CREDENTIALS_FILE" "connect-sync-temp:/tmp/creds.json" 2>/dev/null || true

    # Stop existing containers
    ${pkgs.docker}/bin/docker stop connect-sync connect-api 2>/dev/null || true
    ${pkgs.docker}/bin/docker rm connect-sync connect-api 2>/dev/null || true

    # Start sync container
    echo "Starting Connect sync service..."
    ${pkgs.docker}/bin/docker run -d \
      --name connect-sync \
      --restart unless-stopped \
      -v "$CREDENTIALS_FILE:/home/opuser/.op/1password-credentials.json:ro" \
      -v "${connectDataDir}/data:/home/opuser/.op/data" \
      -e OP_HTTP_PORT=8081 \
      -e OP_BUS_PORT=11221 \
      -e OP_BUS_PEERS=localhost:11220 \
      ${cfg.syncImage}

    # Start API container
    echo "Starting Connect API service..."
    ${pkgs.docker}/bin/docker run -d \
      --name connect-api \
      --restart unless-stopped \
      -p "${toString cfg.port}:${toString cfg.port}" \
      -v "$CREDENTIALS_FILE:/home/opuser/.op/1password-credentials.json:ro" \
      -v "${connectDataDir}/data:/home/opuser/.op/data" \
      -e OP_HTTP_PORT=${toString cfg.port} \
      -e OP_BUS_PORT=11220 \
      -e OP_BUS_PEERS=localhost:11221 \
      ${cfg.image}

    echo "1Password Connect started on port ${toString cfg.port}"
  '';
in {
  options.myConfig.onepassword-connect = {
    enable = mkEnableOption "1Password Connect Server for REST API secret access";

    port = mkOption {
      type = types.port;
      default = 8080;
      description = "Port for Connect REST API (exposed from Colima VM)";
    };

    credentialsFile = mkOption {
      type = types.path;
      default = "/etc/1password-connect-credentials";
      description = ''
        Path to 1Password Connect credentials file.
        Generate with: op connect server create <server-name>
        Then download the 1password-credentials.json file.
      '';
    };

    image = mkOption {
      type = types.str;
      default = "1password/connect-api:1.7.3";
      description = "Docker image for Connect API server";
    };

    syncImage = mkOption {
      type = types.str;
      default = "1password/connect-sync:1.7.3";
      description = "Docker image for Connect sync server";
    };
  };

  config = mkIf cfg.enable {
    # Colima package and helper scripts
    environment.systemPackages = [
      pkgs.colima
      pkgs.docker
      connectColimaScript
      connectStartScript
      (pkgs.writeShellScriptBin "connect-logs" ''
        export PATH="${pkgs.colima}/bin:${pkgs.docker}/bin:$PATH"
        export DOCKER_HOST="unix://${colimaSocket}"
        export LIMA_HOME="${colimaDataDir}/_lima"
        ${pkgs.docker}/bin/docker logs -f connect-api
      '')
      (pkgs.writeShellScriptBin "connect-status" ''
        export PATH="${pkgs.colima}/bin:${pkgs.docker}/bin:$PATH"
        export DOCKER_HOST="unix://${colimaSocket}"
        export LIMA_HOME="${colimaDataDir}/_lima"
        echo "=== Colima Status ==="
        ${pkgs.colima}/bin/colima list | grep "^${colimaProfile}" || echo "Colima VM not running"
        echo ""
        echo "=== Docker Containers ==="
        ${pkgs.docker}/bin/docker ps --filter "name=connect-" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null || echo "No containers running"
        echo ""
        echo "=== Health Check ==="
        if curl -sf http://localhost:${toString cfg.port}/v1/health > /dev/null 2>&1; then
          echo "✓ Connect API is responding"
        else
          echo "✗ Connect API is not responding"
        fi
      '')
    ];

    # Launchd DAEMON (system-wide, runs as root)
    # This ensures Connect starts at boot before user login
    launchd.daemons.onepassword-connect = {
      serviceConfig = {
        Label = "com.1password.connect";
        ProgramArguments = [
          "${pkgs.bash}/bin/bash"
          "-c"
          ''
            set -euo pipefail

            export PATH="${pkgs.colima}/bin:${pkgs.docker}/bin:$PATH"
            export DOCKER_HOST="unix://${colimaSocket}"
            export LIMA_HOME="${colimaDataDir}/_lima"

            LOG_FILE="/var/log/1password-connect.log"
            mkdir -p "$(dirname "$LOG_FILE")"

            log() {
              echo "$(date '+%Y-%m-%d %H:%M:%S') $1" | tee -a "$LOG_FILE"
            }

            log "Starting 1Password Connect service..."

            # Start Colima if not running
            if ! ${pkgs.colima}/bin/colima list 2>/dev/null | grep -q "^${colimaProfile}.*Running"; then
              log "Starting Colima VM..."
              ${connectColimaScript}/bin/connect-colima start
            fi

            # Wait for Docker socket
            log "Waiting for Docker socket..."
            for i in {1..30}; do
              if [ -S "${colimaSocket}" ]; then
                log "Docker socket ready"
                break
              fi
              sleep 1
            done

            if [ ! -S "${colimaSocket}" ]; then
              log "ERROR: Docker socket not available"
              exit 1
            fi

            # Check if containers are running
            API_RUNNING=$(${pkgs.docker}/bin/docker ps --filter "name=connect-api" --format "{{.Names}}" 2>/dev/null || true)
            SYNC_RUNNING=$(${pkgs.docker}/bin/docker ps --filter "name=connect-sync" --format "{{.Names}}" 2>/dev/null || true)

            if [ -z "$API_RUNNING" ] || [ -z "$SYNC_RUNNING" ]; then
              log "Connect containers not running, starting..."
              ${connectStartScript}/bin/connect-start
            else
              log "Connect containers already running"
            fi

            # Keep the service alive by monitoring
            log "Monitoring Connect health..."
            while true; do
              sleep 30

              # Check Colima is still running
              if ! ${pkgs.colima}/bin/colima list 2>/dev/null | grep -q "^${colimaProfile}.*Running"; then
                log "Colima stopped unexpectedly"
                exit 1
              fi

              # Check API health
              if ! curl -sf http://localhost:${toString cfg.port}/v1/health > /dev/null 2>&1; then
                log "WARNING: Connect API not responding"
              fi
            done
          ''
        ];
        RunAtLoad = true;
        KeepAlive = true;
        StandardOutPath = "/var/log/1password-connect.stdout";
        StandardErrorPath = "/var/log/1password-connect.stderr";
        EnvironmentVariables = {
          PATH = "${pkgs.colima}/bin:${pkgs.docker}/bin:/usr/local/bin:/usr/bin:/bin";
          LIMA_HOME = "${colimaDataDir}/_lima";
        };
      };
    };

    # Ensure directories exist
    system.activationScripts.onepassword-connect-dirs = {
      text = ''
        mkdir -p ${colimaDataDir}
        mkdir -p /var/log
      '';
    };
  };
}
