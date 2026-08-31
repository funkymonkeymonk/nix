# Shared LLM client environment variables
# Sets LLM_SERVER_HOST, LLM_SERVER_PORT, OPENCODE_ENDPOINT, and CLAUDE_API_BASE
# when any AI agent role (claude, opencode, pi) is enabled.
# Also owns the myConfig.llmClient, myConfig.sharedModels, and
# myConfig.llmEndpoints option declarations (sharedModels/llmEndpoints have
# no active consumer modules currently — they're legacy declarations kept
# for backward compatibility with hosts that still set them, e.g.
# targets/zero).
{
  config,
  lib,
  ...
}: let
  cfg = config.myConfig.llmClient;
  anyAiRoleActive =
    config.myConfig.roles.claude.enable
    || config.myConfig.roles.opencode.enable
    || config.myConfig.roles.pi.enable;
in {
  options.myConfig.llmClient = {
    serverHost = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = "Default LLM server host for client tools";
    };

    serverPort = lib.mkOption {
      type = lib.types.str;
      default = "8080";
      description = "Default LLM server port for client tools (bifrost gateway)";
    };

    rtk = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable RTK (Rust Token Killer) for token-optimized LLM tool output. Automatically integrates with OpenCode and Claude Code when their respective roles are enabled.";
      };
    };
  };

  options.myConfig.sharedModels = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = ["qwen3.8-27b"];
    description = "Central model configuration for local inference services.";
  };

  options.myConfig.llmEndpoints = lib.mkOption {
    type = lib.types.attrsOf (lib.types.submodule {
      options = {
        host = lib.mkOption {
          type = lib.types.str;
          description = "Host address for the LLM endpoint";
        };
        port = lib.mkOption {
          type = lib.types.str;
          description = "Port for the LLM endpoint";
        };
      };
    });
    default = {};
    description = "Additional LLM endpoint configurations (merged with default localhost endpoint)";
  };

  config = lib.mkIf anyAiRoleActive {
    environment.variables = {
      LLM_SERVER_HOST = cfg.serverHost;
      LLM_SERVER_PORT = cfg.serverPort;
      OPENCODE_ENDPOINT = "http://${cfg.serverHost}:${cfg.serverPort}";
      CLAUDE_API_BASE = "http://${cfg.serverHost}:${cfg.serverPort}";
    };
  };
}
