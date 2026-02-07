{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.myConfig.colima-open-webui;
in {
  options.myConfig.colima-open-webui = {
    enable = mkEnableOption "Open WebUI via Colima";

    port = mkOption {
      type = types.port;
      default = 3000;
      description = "Port for Open WebUI service";
    };
  };

  config = mkIf cfg.enable {
    home = {
      file = {
        # Docker Compose configuration for Open WebUI
        ".config/open-webui/docker-compose.yml" = {
          text = ''
            version: '3.8'
            services:
              open-webui:
                image: ghcr.io/open-webui/open-webui:main
                container_name: open-webui
                ports:
                  - "${toString cfg.port}:8080"
                environment:
                  - OLLAMA_BASE_URL=http://host.docker.internal:11434
                  - WEBUI_SECRET_KEY=open-webui-secret-key
                volumes:
                  - open-webui:/app/backend/data
                restart: unless-stopped
                extra_hosts:
                  - "host.docker.internal:host-gateway"

            volumes:
              open-webui:
          '';
        };

        # Scripts to manage Open WebUI service
        ".local/bin/open-webui-start" = {
          text = ''
            #!/usr/bin/env bash
            set -euo pipefail

            # Ensure Colima is running
            if ! pgrep -f "colima" > /dev/null; then
              echo "Starting Colima..."
              colima start
            fi

            # Start Open WebUI
            cd "$HOME/.config/open-webui"
            docker-compose up -d

            echo "Open WebUI is starting on http://localhost:${toString cfg.port}"
          '';
          executable = true;
        };

        ".local/bin/open-webui-stop" = {
          text = ''
            #!/usr/bin/env bash
            set -euo pipefail

            # Stop Open WebUI
            cd "$HOME/.config/open-webui"
            docker-compose down || true

            echo "Open WebUI stopped"
          '';
          executable = true;
        };
      };

      # Ensure Docker CLI tools are available
      packages = with pkgs; [
        docker-compose
        docker-client
      ];
    };
  };
}
