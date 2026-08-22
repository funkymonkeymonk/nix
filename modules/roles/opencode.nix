# OpenCode role - AI coding assistant with OpenCode
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.myConfig.roles.opencode;
  host = config.myConfig.llmClient.serverHost;
  port = config.myConfig.llmClient.serverPort;
in {
  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      opencode
      rtk
    ];

    # Auto-enable agent-skills
    myConfig.agent-skills.enable = true;

    myConfig.llmClient = {
      serverHost = lib.mkDefault "127.0.0.1";
      serverPort = lib.mkDefault "8080";
    };

    # Auto-configure bifrost as a model provider
    myConfig.opencode.providers.local-bifrost = lib.mkDefault {
      name = "Local Bifrost";
      baseURL = "http://${host}:${port}/v1";
      dynamicModels = true;
    };

    # Auto-configure bifrost as MCP gateway
    # Disabled by default so it doesn't consume context until needed —
    # enable per-session with the /mcp command or by overriding
    # myConfig.opencode.extraMcpServers.bifrost.enabled = true.
    myConfig.opencode.extraMcpServers.bifrost = lib.mkDefault {
      type = "remote";
      url = "http://${host}:${port}/mcp";
      enabled = false;
    };

    # Default global agent instructions — override per-machine with a direct assignment
    myConfig.opencode.agentsMd = lib.mkDefault (builtins.readFile ../common/AGENTS.md);

    environment.shellAliases = {
      llm-status = "curl http://${host}:${port}/status";
    };
    # RTK integration is handled by modules/home-manager/opencode.nix
  };
}
