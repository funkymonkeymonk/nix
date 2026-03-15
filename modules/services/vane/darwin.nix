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

  # Launchd service script
  vaneServiceScript = pkgs.writeShellScript "vane-launchd-service" ''
    set -euo pipefail

    export HOME="${darwinHomeDir}"
    export USER="${primaryUser}"
    export PATH="${pkgs.colima}/bin:${pkgs.docker}/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin"

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
    exec ${vaneStartScript}
  '';
in {
  imports = [./common.nix];

  config = mkIf cfg.enable {
    # Install helper scripts and dependencies (including Caddy for reverse proxy)
    environment.systemPackages = [
      vaneColimaScript
      pkgs.colima
      pkgs.docker
      pkgs.docker-compose
      pkgs.caddy
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

      # Docker commands (use Vane's Colima context)
      "vane.docker" = "DOCKER_HOST=unix://${colimaSocket} docker";
      "vane.ps" = "DOCKER_HOST=unix://${colimaSocket} docker-compose -f ${dockerComposeYaml} ps";
    };

    # Create launchd user agent for Vane
    launchd.user.agents.vane = {
      serviceConfig = {
        Label = "com.vane.service";
        ProgramArguments = ["${vaneServiceScript}"];
        RunAtLoad = true;
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
