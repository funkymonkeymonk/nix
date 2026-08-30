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

    # Prefer the local gateway while keeping the provider map extensible.
    myConfig.opencode.model = lib.mkDefault "local-bifrost/omlx/qwen3.8-27b";

    # Auto-configure bifrost as a model provider
    myConfig.opencode.providers.local-bifrost = lib.mkDefault {
      name = "Local Bifrost";
      npm = "@ai-sdk/openai-compatible";
      apiKey = "bifrost-local";
      baseURL = "http://${host}:${bifrostPort}/v1";
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
