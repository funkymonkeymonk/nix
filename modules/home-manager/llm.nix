{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.myConfig.llm;
in {
  options.myConfig.llm = {
    enable = mkEnableOption "Local LLM infrastructure with llama.cpp and LiteLLM";

    dataDir = mkOption {
      type = types.str;
      default = "/var/lib/llm";
      description = "Directory for storing model files and cache";
    };

    maxStorageSize = mkOption {
      type = types.str;
      default = "1TB";
      description = "Maximum storage size for models before cleanup triggers";
    };

    pinnedModels = mkOption {
      type = types.listOf types.str;
      default = [];
      description = "Models that should never be auto-deleted";
    };

    llamaCpp = {
      enable = mkOption {
        type = types.bool;
        default = cfg.enable;
        defaultText = literalExpression "config.myConfig.llm.enable";
        description = "Enable llama.cpp server";
      };

      port = mkOption {
        type = types.port;
        default = 8080;
        description = "Port for llama.cpp server";
      };

      host = mkOption {
        type = types.str;
        default = "127.0.0.1";
        description = "Host address for llama.cpp server";
      };

      extraArgs = mkOption {
        type = types.listOf types.str;
        default = [];
        description = "Extra arguments to pass to llama.cpp server";
        example = ["--ctx-size" "4096" "--threads" "8"];
      };
    };

    litellm = {
      enable = mkOption {
        type = types.bool;
        default = cfg.enable;
        defaultText = literalExpression "config.myConfig.llm.enable";
        description = "Enable LiteLLM proxy";
      };

      port = mkOption {
        type = types.port;
        default = 4000;
        description = "Port for LiteLLM proxy";
      };

      host = mkOption {
        type = types.str;
        default = "0.0.0.0";
        description = "Host address for LiteLLM proxy";
      };

      tailscale = mkOption {
        type = types.bool;
        default = false;
        description = "Expose LiteLLM through Tailscale";
      };

      configPath = mkOption {
        type = types.str;
        default = "${cfg.dataDir}/litellm-config.yaml";
        description = "Path to LiteLLM configuration file";
      };

      extraConfig = mkOption {
        type = types.attrs;
        default = {};
        description = "Extra configuration for LiteLLM";
        example = {
          model_list = [
            {
              model_name = "llama-3.1-8b";
              litellm_params = {
                model = "ollama/llama3.1:8b";
                api_base = "http://localhost:8080";
              };
            }
          ];
        };
      };
    };

    cleanup = {
      enable = mkOption {
        type = types.bool;
        default = cfg.enable;
        defaultText = literalExpression "config.myConfig.llm.enable";
        description = "Enable automatic model cleanup";
      };

      interval = mkOption {
        type = types.str;
        default = "daily";
        description = "How often to run cleanup (systemd.timer format)";
      };

      threshold = mkOption {
        type = types.int;
        default = 80;
        description = "Percentage of storage usage that triggers cleanup";
      };
    };
  };

  config = mkIf cfg.enable {
    # Create data directory with proper permissions (macOS doesn't use systemd)
    system.activationScripts.llm-dirs = ''
      mkdir -p "${cfg.dataDir}/models"
      mkdir -p "${cfg.dataDir}/cache"
      chmod 755 "${cfg.dataDir}"
      chmod 755 "${cfg.dataDir}/models"
      chmod 755 "${cfg.dataDir}/cache"
    '';

    # Add litellm to system packages (using pip for now)
    environment.systemPackages = with pkgs; [
      (pkgs.python311Packages.litellm or (pkgs.python311.withPackages (ps: [ps.pip])))
      ollama
    ];

    # Services configuration
    launchd.daemons = {
      llamacpp = mkIf cfg.llamaCpp.enable {
        script = ''
          # Data directories are created by systemd tmpfiles

          # Start llama.cpp server (using ollama for now as placeholder)
          exec ${pkgs.ollama}/bin/ollama serve \
            --host ${cfg.llamaCpp.host} \
            --port ${toString cfg.llamaCpp.port} \
            --model-path "${cfg.dataDir}/models" \
            --cache-path "${cfg.dataDir}/cache" \
            ${concatStringsSep " " cfg.llamaCpp.extraArgs}
        '';

        serviceConfig = {
          KeepAlive = true;
          RunAtLoad = true;
          StandardOutPath = "${cfg.dataDir}/llamacpp.log";
          StandardErrorPath = "${cfg.dataDir}/llamacpp.error.log";
          UserName = "root";
          GroupName = "wheel";
        };
      };

      litellm = mkIf cfg.litellm.enable {
        script = ''
          # Generate LiteLLM configuration
          mkdir -p "$(dirname "${cfg.litellm.configPath}")"

          cat > "${cfg.litellm.configPath}" << 'EOF'
          model_list:
            - model_name: "local-*"
              litellm_params:
                model: "ollama/*"
                api_base: "http://${cfg.llamaCpp.host}:${toString cfg.llamaCpp.port}"

          litellm_settings:
            drop_params: true
            set_verbose: true

          general_settings:
            master_key: "sk-1234"  # Change this in production!
          EOF

          # Start LiteLLM
          exec ${pkgs.python311Packages.litellm}/bin/litellm \
            --config "${cfg.litellm.configPath}" \
            --port ${toString cfg.litellm.port} \
            --host ${cfg.litellm.host}
        '';

        serviceConfig = {
          KeepAlive = true;
          RunAtLoad = true;
          StandardOutPath = "${cfg.dataDir}/litellm.log";
          StandardErrorPath = "${cfg.dataDir}/litellm.error.log";
          UserName = "root";
          GroupName = "wheel";
        };
      };

      llm-cleanup = mkIf cfg.cleanup.enable {
        script = ''
                  # Check storage usage
                  USAGE=$(df "${cfg.dataDir}" | awk 'NR==2 {print $5}' | sed 's/%//')

                  if [ "$USAGE" -gt ${toString cfg.cleanup.threshold} ]; then
                    # Run LRU cleanup for non-pinned models
                    ${pkgs.python311}/bin/python3 << EOF
          import os
          import json
          import time
          from pathlib import Path

          models_dir = Path("${cfg.dataDir}/models")
          pinned_models = ${builtins.toJSON cfg.pinnedModels}

          # Get model access times and sizes
          model_info = []
          for model_dir in models_dir.iterdir():
              if model_dir.is_dir():
                  # Skip pinned models
                  if any(pinned in str(model_dir) for pinned in pinned_models):
                      continue

                  access_time = model_dir.stat().st_atime
                  size = sum(f.stat().st_size for f in model_dir.rglob('*') if f.is_file())
                  model_info.append((access_time, size, model_dir))

          # Sort by access time (oldest first)
          model_info.sort(key=lambda x: x[0])

          # Delete oldest models until usage is acceptable
          target_usage = ${toString (cfg.cleanup.threshold - 10)}
          current_usage = $USAGE

          for access_time, size, model_dir in model_info:
              if current_usage <= target_usage:
                  break

              print(f"Deleting old model: {model_dir.name} ({size / (1024**3):.1f}GB)")
              import shutil
              shutil.rmtree(model_dir)

              # Update usage (approximate)
              current_usage -= (size / (1024**3)) / (df_output['total'] / (1024**3)) * 100
          EOF
                  fi
        '';

        serviceConfig = {
          StartInterval = 86400; # Daily
          StandardOutPath = "${cfg.dataDir}/cleanup.log";
          StandardErrorPath = "${cfg.dataDir}/cleanup.error.log";
          UserName = "root";
          GroupName = "wheel";
        };
      };
    };
  };
}
