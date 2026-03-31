# Pi role - AI coding assistant with Pi
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.myConfig.roles.pi;
  host = config.myConfig.llmClient.serverHost;
  port = config.myConfig.llmClient.serverPort;
in {
  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      pi-coding-agent
      rtk
    ];

    # Auto-enable agent-skills
    myConfig.agent-skills.enable = true;

    # Enable pi configuration management via home-manager
    myConfig.pi.enable = true;

    # Use mkDefault so opencode wins if both are enabled
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

    # Initialize rtk for Pi on activation
    home-manager.users.monkey = {
      home.activation.rtkInitPi = ''
        if command -v rtk &> /dev/null; then
          # Pi doesn't have native rtk hook support yet
          # rtk commands can still be used manually
          $DRY_RUN_CMD echo "rtk installed for Pi. Use 'rtk <command>' manually." 2>/dev/null || true
        fi
      '';
    };
  };
}
