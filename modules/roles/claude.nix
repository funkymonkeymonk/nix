# Claude Code role - AI coding assistant with Claude
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.myConfig.roles.claude;
  host = config.myConfig.llmClient.serverHost;
  port = config.myConfig.llmClient.serverPort;
in {
  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      claude-code
      rtk
    ];

    # Auto-enable agent-skills
    myConfig.agent-skills.enable = true;

    # Use mkDefault so opencode wins if both are enabled
    myConfig.llmClient = {
      serverHost = lib.mkDefault "127.0.0.1";
      serverPort = lib.mkDefault "8080";
    };

    # Auto-configure bifrost as MCP gateway
    myConfig.claude-code.mcpServers.bifrost = lib.mkDefault {
      type = "remote";
      url = "http://${host}:${port}/mcp";
      enabled = true;
    };

    environment.shellAliases = {
      llm-status = "curl http://${host}:${port}/status";
    };
    # RTK integration is handled by modules/home-manager/claude-code.nix
  };
}
