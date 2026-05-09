# 1Password Connect Server module for Darwin (macOS)
# Runs Connect containers directly via Docker (no Colima VM)
# https://developer.1password.com/docs/connect
{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.myConfig.onepassword-connect;

  # Connect data directory
  connectDataDir = "/var/lib/1password-connect";
in {
  options.myConfig.onepassword-connect = {
    enable = mkEnableOption "1Password Connect Server for REST API secret access";

    port = mkOption {
      type = types.port;
      default = 8080;
      description = "Port for Connect REST API";
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
    # Docker and helper scripts
    environment.systemPackages = [
      pkgs.docker
      (pkgs.writeShellScriptBin "connect-logs" ''
        ${pkgs.docker}/bin/docker logs -f connect-api
      '')
      (pkgs.writeShellScriptBin "connect-status" ''
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
    launchd.daemons.onepassword-connect = {
      serviceConfig = {
        Label = "com.1password.connect";
        ProgramArguments = [
          "${pkgs.bash}/bin/bash"
          "-c"
          ''
            set -euo pipefail

            LOG_FILE="/var/log/1password-connect.log"
            mkdir -p "$(dirname "$LOG_FILE")" ${connectDataDir}/data

            log() {
              echo "$(date '+%Y-%m-%d %H:%M:%S') $1" | tee -a "$LOG_FILE"
            }

            log "Starting 1Password Connect service..."

            # Check for credentials
            if [ ! -f "${cfg.credentialsFile}" ]; then
              log "ERROR: Connect credentials not found at ${cfg.credentialsFile}"
              log "To set up: op connect server create <name>"
              log "Then save credentials to ${cfg.credentialsFile}"
              exit 1
            fi

            # Wait for Docker to be available
            log "Waiting for Docker..."
            for i in {1..30}; do
              if ${pkgs.docker}/bin/docker info > /dev/null 2>&1; then
                log "Docker is available"
                break
              fi
              if [ $i -eq 30 ]; then
                log "ERROR: Docker not available after 30 seconds"
                exit 1
              fi
              sleep 1
            done

            # Check if containers are running
            API_RUNNING=$(${pkgs.docker}/bin/docker ps --filter "name=connect-api" --format "{{.Names}}" 2>/dev/null || true)
            SYNC_RUNNING=$(${pkgs.docker}/bin/docker ps --filter "name=connect-sync" --format "{{.Names}}" 2>/dev/null || true)

            if [ -z "$API_RUNNING" ] || [ -z "$SYNC_RUNNING" ]; then
              log "Starting Connect containers..."

              # Stop any existing containers
              ${pkgs.docker}/bin/docker stop connect-sync connect-api 2>/dev/null || true
              ${pkgs.docker}/bin/docker rm connect-sync connect-api 2>/dev/null || true

              # Start sync container
              log "Starting sync service..."
              ${pkgs.docker}/bin/docker run -d \
                --name connect-sync \
                --restart unless-stopped \
                -v "${cfg.credentialsFile}:/home/opuser/.op/1password-credentials.json:ro" \
                -v "${connectDataDir}/data:/home/opuser/.op/data" \
                -e OP_HTTP_PORT=8081 \
                -e OP_BUS_PORT=11221 \
                -e OP_BUS_PEERS=localhost:11220 \
                ${cfg.syncImage}

              # Start API container
              log "Starting API service..."
              ${pkgs.docker}/bin/docker run -d \
                --name connect-api \
                --restart unless-stopped \
                -p "${toString cfg.port}:${toString cfg.port}" \
                -v "${cfg.credentialsFile}:/home/opuser/.op/1password-credentials.json:ro" \
                -v "${connectDataDir}/data:/home/opuser/.op/data" \
                -e OP_HTTP_PORT=${toString cfg.port} \
                -e OP_BUS_PORT=11220 \
                -e OP_BUS_PEERS=localhost:11221 \
                ${cfg.image}

              log "Connect started on port ${toString cfg.port}"
            else
              log "Connect containers already running"
            fi

            # Keep the service alive by monitoring
            log "Monitoring Connect health..."
            while true; do
              sleep 30

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
          PATH = "${pkgs.docker}/bin:/usr/local/bin:/usr/bin:/bin";
        };
      };
    };

    # Ensure directories exist
    system.activationScripts.onepassword-connect-dirs = {
      text = ''
        mkdir -p ${connectDataDir}/data
        mkdir -p /var/log
      '';
    };
  };
}
