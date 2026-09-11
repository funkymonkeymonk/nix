# OpenCode role - AI coding assistant with OpenCode
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.myConfig.roles.opencode;
  host = config.myConfig.llmClient.serverHost;
  bifrostPort = toString (config.myConfig.bifrost.port or 8081);
in {
  options.myConfig.roles.opencode.enable = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = "OpenCode AI assistant with rtk";
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      opencode
      rtk
    ];

    # Auto-enable agent-skills
    myConfig.agent-skills.enable = true;
    myConfig.opencode.enable = true;

    myConfig.llmClient = {
      serverHost = lib.mkDefault "127.0.0.1";
      serverPort = lib.mkDefault "8080";
    };

    # Auto-configure Bifrost as a model provider. Model selection is handled by
    # the discovery plugin rather than pinned in the generated config.
    myConfig.opencode.providers.local-bifrost = lib.mkDefault {
      name = "Local Bifrost";
      npm = "@ai-sdk/anthropic";
      apiKey = "bifrost-local";
      baseURL = "http://${host}:${bifrostPort}/anthropic/v1";
      models."omlx/qwen3.8-27b" = {
        name = "Qwen3.8 27B (oMLX)";
      };
      dynamicModels = true;
    };

    # Auto-configure bifrost as MCP gateway
    # Disabled by default so it doesn't consume context until needed —
    # enable per-session with the /mcp command or by overriding
    # myConfig.opencode.extraMcpServers.bifrost.enabled = true.
    myConfig.opencode.extraMcpServers.bifrost = lib.mkDefault {
      type = "remote";
      url = "http://${host}:${bifrostPort}/mcp";
      enabled = false;
    };

    # Default global agent instructions — override per-machine with a direct assignment
    myConfig.opencode.agentsMd = lib.mkDefault (builtins.readFile ../common/AGENTS.md);

    # RTK integration is handled by modules/home-manager/opencode.nix
  };
}
