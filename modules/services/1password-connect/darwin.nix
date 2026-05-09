# 1Password Connect Server module for Darwin (macOS)
# Runs Connect via Colima VM for container support on macOS
# https://developer.1password.com/docs/connect
{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.myConfig.onepassword-connect;

  # Get primary user for paths
  primaryUser =
    if config.myConfig.users != []
    then (builtins.head config.myConfig.users).name
    else "monkey";

  homeDir = "/Users/${primaryUser}";
  colimaProfile = "connect";
  colimaSocket = "${homeDir}/.colima/${colimaProfile}/docker.sock";
  connectDataDir = "${homeDir}/.local/share/1password-connect";
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
      description = "Container image for Connect API server";
    };

    syncImage = mkOption {
      type = types.str;
      default = "1password/connect-sync:1.7.3";
      description = "Container image for Connect sync server";
    };
  };

  config = mkIf cfg.enable {
    # Colima and helper scripts
    environment.systemPackages = [
      pkgs.colima
      pkgs.docker
      (pkgs.writeShellScriptBin "connect-colima" ''
        set -euo pipefail
        export PATH="${pkgs.colima}/bin:${pkgs.docker}/bin:$PATH"

        COMMAND=''${1:-status}
        case "$COMMAND" in
          start)
            if colima list | grep -q "^${colimaProfile}"; then
              if colima list | grep "^${colimaProfile}" | grep -q "Running"; then
                echo "Colima VM already running"
              else
                echo "Starting Colima VM..."
                colima start ${colimaProfile}
              fi
            else
              echo "Creating Colima VM..."
              colima start ${colimaProfile} --cpu 2 --memory 2 --disk 10 --vm-type vz
            fi
            ;;
          stop)
            colima stop ${colimaProfile} 2>/dev/null || true
            ;;
          status)
            colima list | grep "^${colimaProfile}" || echo "VM not found"
            ;;
          *)
            echo "Usage: connect-colima {start|stop|status}"
            ;;
        esac
      '')
      (pkgs.writeShellScriptBin "connect-start" ''
        set -euo pipefail
        export PATH="${pkgs.colima}/bin:${pkgs.docker}/bin:$PATH"
        export DOCKER_HOST="unix://${colimaSocket}"

        # Start Colima if needed
        if ! colima list 2>/dev/null | grep -q "^${colimaProfile}.*Running"; then
          echo "Starting Colima VM..."
          connect-colima start
          echo "Waiting for Docker..."
          for i in {1..30}; do
            [ -S "${colimaSocket}" ] && break
            sleep 1
          done
        fi

        # Start Connect containers
        echo "Starting Connect containers..."
        docker stop connect-sync connect-api 2>/dev/null || true
        docker rm connect-sync connect-api 2>/dev/null || true

        docker run -d --name connect-sync \
          -v "${cfg.credentialsFile}:/home/opuser/.op/1password-credentials.json:ro" \
          -e OP_BUS_PEERS=localhost:11220 \
          ${cfg.syncImage}

        docker run -d --name connect-api -p "${toString cfg.port}:${toString cfg.port}" \
          -v "${cfg.credentialsFile}:/home/opuser/.op/1password-credentials.json:ro" \
          -e OP_BUS_PEERS=localhost:11221 \
          ${cfg.image}

        echo "Connect started on port ${toString cfg.port}"
      '')
      (pkgs.writeShellScriptBin "connect-logs" ''
        export DOCKER_HOST="unix://${colimaSocket}"
        docker logs -f connect-api
      '')
      (pkgs.writeShellScriptBin "connect-status" ''
        export DOCKER_HOST="unix://${colimaSocket}"
        echo "=== Colima VM ==="
        colima list | grep "^${colimaProfile}" || echo "Not running"
        echo ""
        echo "=== Containers ==="
        docker ps --filter "name=connect-" 2>/dev/null || echo "No containers"
        echo ""
        echo "=== Health ==="
        curl -sf http://localhost:${toString cfg.port}/v1/health >/dev/null 2>&1 && echo "✓ Ready" || echo "✗ Not responding"
      '')
    ];

    # Launchd USER AGENT - starts when user logs in
    # Colima requires user session, so this runs as user agent
    launchd.user.agents.onepassword-connect = {
      serviceConfig = {
        Label = "com.1password.connect";
        ProgramArguments = [
          "${pkgs.bash}/bin/bash"
          "-c"
          ''
            set -euo pipefail
            export PATH="${pkgs.colima}/bin:${pkgs.docker}/bin:$PATH"
            export DOCKER_HOST="unix://${colimaSocket}"

            LOG="${homeDir}/Library/Logs/1password-connect.log"
            mkdir -p "$(dirname "$LOG")"

            log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $1" | tee -a "$LOG"; }

            # Check credentials exist
            if [ ! -f "${cfg.credentialsFile}" ]; then
              log "ERROR: Credentials not found at ${cfg.credentialsFile}"
              log "Run: op connect server create <name>"
              exit 1
            fi

            # Start Colima if not running
            if ! colima list 2>/dev/null | grep -q "^${colimaProfile}.*Running"; then
              log "Starting Colima VM..."
              colima start ${colimaProfile} --cpu 2 --memory 2 --disk 10 --vm-type vz 2>/dev/null || true
            fi

            # Wait for Docker
            for i in {1..30}; do
              [ -S "${colimaSocket}" ] && break
              sleep 1
            done

            if [ ! -S "${colimaSocket}" ]; then
              log "ERROR: Docker socket not available"
              exit 1
            fi

            # Start containers if not running
            if ! docker ps | grep -q connect-api; then
              log "Starting Connect containers..."
              docker stop connect-sync connect-api 2>/dev/null || true
              docker rm connect-sync connect-api 2>/dev/null || true

              docker run -d --name connect-sync \
                -v "${cfg.credentialsFile}:/home/opuser/.op/1password-credentials.json:ro" \
                -e OP_BUS_PEERS=localhost:11220 \
                ${cfg.syncImage}

              docker run -d --name connect-api -p "${toString cfg.port}:${toString cfg.port}" \
                -v "${cfg.credentialsFile}:/home/opuser/.op/1password-credentials.json:ro" \
                -e OP_BUS_PEERS=localhost:11221 \
                ${cfg.image}

              log "Connect started"
            fi

            # Monitor
            while true; do
              sleep 30
              if ! curl -sf http://localhost:${toString cfg.port}/v1/health >/dev/null 2>&1; then
                log "WARNING: Connect not responding"
              fi
            done
          ''
        ];
        RunAtLoad = true;
        KeepAlive = true;
        StandardOutPath = "${homeDir}/Library/Logs/1password-connect.stdout";
        StandardErrorPath = "${homeDir}/Library/Logs/1password-connect.stderr";
      };
    };

    # Ensure directories exist
    system.activationScripts.onepassword-connect-dirs = {
      text = ''
        mkdir -p ${connectDataDir}
        mkdir -p ${homeDir}/Library/Logs
        chown ${primaryUser}:staff ${homeDir}/Library/Logs
      '';
    };
  };
}
