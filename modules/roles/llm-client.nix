{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.myConfig.roles.llm-client;
  host = config.myConfig.llmClient.serverHost;
  port = config.myConfig.llmClient.serverPort;
in {
  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      opencode
      rtk
    ];

    # Auto-enable agent-skills
    myConfig.roles.agent-skills.enable = true;

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
  };
}
