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
      serverPort = lib.mkDefault "11434";
    };

    environment.variables = {
      LLM_SERVER_HOST = host;
      LLM_SERVER_PORT = port;
      OPENCODE_ENDPOINT = "http://${host}:${port}";
      CLAUDE_API_BASE = "http://${host}:${port}";
    };

    environment.shellAliases = {
      llm-status = "curl http://${host}:${port}/status";
    };

    # Initialize rtk for Claude Code
    home-manager.users.monkey = {
      home.activation.rtkInitClaude = lib.hm.dag.entryAfter ["writeBoundary"] ''
        if command -v rtk &> /dev/null; then
          $DRY_RUN_CMD rtk init -g 2>/dev/null || true
        fi
      '';
    };
  };
}
