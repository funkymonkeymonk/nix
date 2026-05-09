# 1Password Connect Server module for Darwin (macOS)
# Runs Connect as user agent (requires manual start on headless servers)
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
    else "root";

  homeDir = "/Users/${primaryUser}";
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
    # Helper scripts
    environment.systemPackages = [
      (pkgs.writeShellScriptBin "connect-start" ''
        set -euo pipefail

        export PATH="${pkgs.docker}/bin:$PATH"
        CREDENTIALS_FILE="${cfg.credentialsFile}"
        DATA_DIR="${connectDataDir}"

        mkdir -p "$DATA_DIR"

        if [ ! -f "$CREDENTIALS_FILE" ]; then
          echo "ERROR: Credentials not found at $CREDENTIALS_FILE"
          exit 1
        fi

        echo "Starting 1Password Connect..."

        # Stop existing
        docker stop connect-sync connect-api 2>/dev/null || true
        docker rm connect-sync connect-api 2>/dev/null || true

        # Start sync
        docker run -d \
          --name connect-sync \
          --restart unless-stopped \
          -v "$CREDENTIALS_FILE:/home/opuser/.op/1password-credentials.json:ro" \
          -v "$DATA_DIR:/home/opuser/.op/data" \
          -e OP_HTTP_PORT=8081 \
          -e OP_BUS_PORT=11221 \
          -e OP_BUS_PEERS=localhost:11220 \
          ${cfg.syncImage}

        # Start API
        docker run -d \
          --name connect-api \
          --restart unless-stopped \
          -p "${toString cfg.port}:${toString cfg.port}" \
          -v "$CREDENTIALS_FILE:/home/opuser/.op/1password-credentials.json:ro" \
          -v "$DATA_DIR:/home/opuser/.op/data" \
          -e OP_HTTP_PORT=${toString cfg.port} \
          -e OP_BUS_PORT=11220 \
          -e OP_BUS_PEERS=localhost:11221 \
          ${cfg.image}

        echo "Connect started on port ${toString cfg.port}"
      '')
      (pkgs.writeShellScriptBin "connect-logs" ''
        docker logs -f connect-api
      '')
      (pkgs.writeShellScriptBin "connect-status" ''
        echo "=== Docker Containers ==="
        docker ps --filter "name=connect-" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null || echo "No containers"
        echo ""
        echo "=== Health Check ==="
        if curl -sf http://localhost:${toString cfg.port}/v1/health > /dev/null 2>&1; then
          echo "✓ Connect API is responding"
        else
          echo "✗ Connect API is not responding"
        fi
      '')
    ];

    # Note: On Darwin headless servers, Docker/Podman/Colima all require
    # a user session. For now, start Connect manually after login:
    #   connect-start
    #
    # Future: Use native macOS virtualization (tart/vfkit) or
    # install Docker Desktop and start it automatically.

    # Ensure data directory exists
    system.activationScripts.onepassword-connect-dirs = {
      text = ''
        mkdir -p ${connectDataDir}
        chown ${primaryUser}:staff ${connectDataDir}
      '';
    };
  };
}
