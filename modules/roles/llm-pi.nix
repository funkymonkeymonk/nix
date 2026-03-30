{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.myConfig.roles.llm-pi;
  host = config.myConfig.llmClient.serverHost;
  port = config.myConfig.llmClient.serverPort;
in {
  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      pi-coding-agent
    ];

    # Auto-enable agent-skills
    myConfig.roles.agent-skills.enable = true;

    # Enable pi configuration management via home-manager
    myConfig.pi.enable = true;

    # Use mkDefault so llm-client wins if both are enabled
    myConfig.llmClient = {
      serverHost = lib.mkDefault "127.0.0.1";
      serverPort = lib.mkDefault "11434";
    };

    environment.variables = {
      LLM_SERVER_HOST = host;
      LLM_SERVER_PORT = port;
      PI_CODING_AGENT_DIR = "$HOME/.pi/agent";
    };

    environment.shellAliases = {
      llm-status = "curl http://${host}:${port}/status";
      pi-status = "ls -la ~/.pi/agent";
      pi-sessions = "ls -la ~/.pi/agent/sessions 2>/dev/null || echo 'No sessions yet'";
      pi-config = "cat ~/.pi/agent/settings.json 2>/dev/null || echo 'No settings file'";
    };
  };
}
