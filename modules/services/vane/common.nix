# Vane (formerly Perplexica) service module - Common configuration
#
# Vane is an AI-powered answering engine that uses web search (via SearxNG)
# combined with LLMs to provide accurate answers with cited sources.
# Supports local LLMs via Ollama and cloud providers.
{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.myConfig.vane;

  # Environment variables for the service
  serviceEnvironment =
    {
      VANE_PORT = toString cfg.port;
      SEARXNG_API_URL = cfg.searxngUrl;
    }
    // optionalAttrs (cfg.ollamaUrl != null) {
      OLLAMA_API_URL = cfg.ollamaUrl;
    }
    // optionalAttrs (cfg.openaiApiKey != null) {
      OPENAI_API_KEY = cfg.openaiApiKey;
    }
    // optionalAttrs (cfg.anthropicApiKey != null) {
      ANTHROPIC_API_KEY = cfg.anthropicApiKey;
    }
    // cfg.extraEnvironment;

  # Vane configuration file with Ollama pre-configured
  vaneConfigToml = pkgs.writeText "vane-config.toml" ''
    [GENERAL]
    PORT = 3001
    SIMILARITY_MEASURE = "cosine"
    KEEP_ALIVE = "5m"

    [API_KEYS]
    OPENAI = ""
    GROQ = ""
    ANTHROPIC = ""
    GEMINI = ""

    [API_ENDPOINTS]
    SEARXNG = "${cfg.searxngUrl}"
    OLLAMA = "${cfg.ollamaUrl}"
  '';

  # Docker compose configuration for Vane + SearxNG
  dockerComposeYaml = pkgs.writeText "vane-docker-compose.yaml" (builtins.toJSON {
    services =
      {
        vane = {
          image = "itzcrazykns1337/vane:latest";
          container_name = "vane";
          ports = ["${toString cfg.port}:3000"];
          environment = serviceEnvironment;
          volumes = [
            "${cfg.dataDir}/vane:/home/vane/data"
            "${vaneConfigToml}:/tmp/vane-config.toml:ro"
          ];
          restart = "unless-stopped";
          networks = ["vane-network"];
          depends_on = optional cfg.embeddedSearxng "searxng";
        };
      }
      // optionalAttrs cfg.embeddedSearxng {
        searxng = {
          image = "searxng/searxng:latest";
          container_name = "vane-searxng";
          ports = ["${toString cfg.searxngPort}:8080"];
          volumes = [
            "${cfg.dataDir}/searxng:/etc/searxng"
          ];
          restart = "unless-stopped";
          networks = ["vane-network"];
          environment = {
            SEARXNG_SETTINGS_PATH = "/etc/searxng/settings.yml";
          };
        };
      };
    networks = {
      vane-network = {
        driver = "bridge";
      };
    };
    volumes =
      {
        vane-data = {
          driver = "local";
        };
      }
      // optionalAttrs cfg.embeddedSearxng {
        searxng-data = {
          driver = "local";
        };
      };
  });

  # Check if Docker is available (works with Colima, Docker Desktop, etc.)
  checkDockerScript = pkgs.writeShellScript "vane-check-docker" ''
    if ! command -v docker > /dev/null 2>&1; then
      echo "ERROR: Docker CLI not found."
      echo ""
      echo "Vane requires Docker to run containers."
      ${optionalString config.myConfig.isDarwin "echo 'On macOS, Docker is provided by Colima (already installed).'"}
      echo ""
      exit 1
    fi

    if ! docker info > /dev/null 2>&1; then
      echo "ERROR: Docker daemon is not running."
      echo ""
      echo "Vane requires a running Docker daemon."
      ${optionalString config.myConfig.isDarwin "
      echo ''
      echo 'To start Docker with Colima:'
      echo '  colima start'
      echo ''
      echo 'Or with VM settings for better performance:'
      echo '  colima start --cpu 4 --memory 8'
      "}
      echo ""
      exit 1
    fi
  '';

  # Start script that launches Docker containers
  vaneStartScript = pkgs.writeShellScript "vane-start" ''
    set -euo pipefail

    # Check Docker is available first
    ${checkDockerScript}

    DATA_DIR="${cfg.dataDir}"
    COMPOSE_FILE="${dockerComposeYaml}"

    # Create data directories
    mkdir -p "$DATA_DIR/vane"
    ${optionalString cfg.embeddedSearxng "mkdir -p \"$DATA_DIR/searxng\""}

    # Copy pre-configured Vane config if it doesn't exist
    if [ ! -f "$DATA_DIR/vane/config.toml" ]; then
      echo "Setting up Vane configuration with Ollama..."
      cp "${vaneConfigToml}" "$DATA_DIR/vane/config.toml"
    fi

    # Create SearxNG settings if embedded and not exists
    ${optionalString cfg.embeddedSearxng ''
        if [ ! -f "$DATA_DIR/searxng/settings.yml" ]; then
          mkdir -p "$DATA_DIR/searxng"
          cat > "$DATA_DIR/searxng/settings.yml" << 'SEARXNG_CONFIG'
      use_default_settings: true

      server:
        bind_address: "0.0.0.0"
        port: 8080
        secret_key: "$(openssl rand -hex 32)"

      search:
        formats:
          - html
          - json

      engines:
        - name: wolframalpha
          engine: wolframalpha
          shortcut: wa
          disabled: false
      SEARXNG_CONFIG
        fi
    ''}

    # Pull images and start containers
    echo "Starting Vane containers..."
    ${pkgs.docker-compose}/bin/docker-compose -f "$COMPOSE_FILE" pull
    ${pkgs.docker-compose}/bin/docker-compose -f "$COMPOSE_FILE" up -d

    echo ""
    echo "Vane is starting up..."
    echo "Web UI: http://localhost:${toString cfg.port}"
    ${optionalString cfg.embeddedSearxng "echo \"SearxNG:  http://localhost:${toString cfg.searxngPort}\""}
    echo ""
    echo "Note: First startup may take a few minutes to download images."
    echo "Use 'vane-ctl logs' to view startup progress."
  '';

  # Stop script
  vaneStopScript = pkgs.writeShellScript "vane-stop" ''
    set -euo pipefail

    # Check Docker is available
    if ! command -v docker > /dev/null 2>&1 || ! docker info > /dev/null 2>&1; then
      echo "Docker is not running - containers are already stopped."
      exit 0
    fi

    COMPOSE_FILE="${dockerComposeYaml}"

    echo "Stopping Vane containers..."
    ${pkgs.docker-compose}/bin/docker-compose -f "$COMPOSE_FILE" down || true
    echo "Vane stopped"
  '';

  # Status check script
  vaneStatusScript = pkgs.writeShellScript "vane-status" ''
    set -euo pipefail

    # Check Docker is available
    if ! command -v docker > /dev/null 2>&1; then
      echo "Docker CLI not found."
      exit 1
    fi

    if ! docker info > /dev/null 2>&1; then
      echo "Docker daemon is not running."
      echo ""
      echo "To start Docker with Colima:"
      echo "  colima start"
      exit 1
    fi

    COMPOSE_FILE="${dockerComposeYaml}"

    ${pkgs.docker-compose}/bin/docker-compose -f "$COMPOSE_FILE" ps
  '';
in {
  # Internal option for sharing values between modules (not user-facing)
  options._vaneCommon = mkOption {
    type = types.attrs;
    internal = true;
    description = "Internal: Shared Vane configuration values";
  };

  # Export shared values for use by the platform-specific modules
  config._vaneCommon = {
    inherit
      serviceEnvironment
      dockerComposeYaml
      vaneConfigToml
      checkDockerScript
      vaneStartScript
      vaneStopScript
      vaneStatusScript
      ;
  };
}
