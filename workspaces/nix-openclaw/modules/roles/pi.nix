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

    # Install Pi RTK extension for automatic token optimization
    # The extension intercepts bash tool calls and rewrites them via rtk
    home-manager.users.monkey = {
      home.file = {
        ".pi/agent/extensions/pi-rtk/src/index.ts".source =
          ../../home-manager/skills/external/pi-rtk/src/index.ts;
        ".pi/agent/extensions/pi-rtk/package.json".source =
          ../../home-manager/skills/external/pi-rtk/package.json;
        ".pi/agent/extensions/pi-rtk/README.md".source =
          ../../home-manager/skills/external/pi-rtk/README.md;
        ".pi/agent/extensions/pi-rtk/LICENSE".source =
          ../../home-manager/skills/external/pi-rtk/LICENSE;
      };

      # Add the extension path to pi settings
      home.file.".pi/agent/settings.json".text =
        lib.optionalString
        (config.myConfig.pi.settings == {})
        ''
          {
            "extensions": ["~/.pi/agent/extensions/pi-rtk/src/index.ts"]
          }
        '';
    };
  };
}
