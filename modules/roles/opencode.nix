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
    myConfig.opencode.providers.bifrost = lib.mkDefault {
      name = "Bifrost AI Gateway";
      baseURL = "http://${host}:${port}/v1";
      dynamicModels = true;
    };

    # Auto-configure bifrost as MCP gateway
    myConfig.opencode.extraMcpServers.bifrost = lib.mkDefault {
      type = "remote";
      url = "http://${host}:${port}/mcp";
      enabled = true;
    };

    environment.shellAliases = {
      llm-status = "curl http://${host}:${port}/status";
    };
    # RTK integration is handled by modules/home-manager/opencode.nix
  };
}
