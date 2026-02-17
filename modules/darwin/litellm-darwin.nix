{
  lib,
  pkgs,
  config,
  ...
}: {
  options.services.litellm = {
    enable = lib.mkEnableOption "LiteLLM - unified LLM API gateway";

    host = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = "Host to bind to";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 4000;
      description = "Port to listen on";
    };

    modelList = lib.mkOption {
      type = lib.types.listOf lib.types.attrs;
      default = [];
      description = "Model list configuration";
    };

    masterKeyFile = lib.mkOption {
      type = lib.types.path;
      default = "/run/secrets/litellmMasterKey";
      description = "Path to file containing master key";
    };
  };

  config = let
    cfg = config.services.litellm;
  in
    lib.mkIf cfg.enable {
      environment = lib.mkMerge [
        {
          systemPackages = with pkgs; [
            colima
            docker-compose
          ];
        }
        {
          etc."litellm/docker-compose.yml".text = let
            modelListStr = lib.generators.toYAML {} cfg.modelList;
          in ''
            services:
              litellm:
                image: litellm/litellm:latest
                ports:
                  - "${toString cfg.port}:4000"
                environment:
                  - LITELLM_MASTER_KEY_FILE=/run/secrets/litellmMasterKey
                  - DATABASE_URL=sqlite:////data/litellm.db
                  - OLLAMA_HOST=http://host.docker.internal:11434
                volumes:
                  - litellm_data:/data
                secrets:
                  - litellm_master_key
                restart: unless-stopped
                extra_hosts:
                  - "host.docker.internal:host-gateway"

            secrets:
              litellm_master_key:
                file: ${cfg.masterKeyFile}

            volumes:
              litellm_data:
          '';

          etc."litellm/config.yaml".text = let
            modelListStr = lib.generators.toYAML {} cfg.modelList;
          in ''
            model_list:
            ${modelListStr}

            general_settings:
              master_key: ${cfg.masterKeyFile}
              database_type: "sqlite"
              database_url: "sqlite:////data/litellm.db"
              use_any_provider: false

            litellm_settings:
              max_parallel_requests: 10
              request_timeout: 300

            environment_variables:
              OLLAMA_HOST: "http://host.docker.internal:11434"
          '';
        }
        {
          variables = {
            LITELLM_HOST = "http://localhost:${toString cfg.port}";
          };
        }
      ];

      launchd.daemons.litellm = {
        serviceConfig = {
          Label = "com.litellm.service";
          ProgramArguments = [
            "/usr/bin/env"
            "bash"
            "-c"
            "cd /etc/litellm && docker-compose up"
          ];
          RunAtLoad = true;
          KeepAlive = true;
          StandardOutPath = "/var/log/litellm.log";
          StandardErrorPath = "/var/log/litellm.log";
        };
      };
    };
}
