# Pi role - AI coding assistant with Pi
{
  config,
  lib,
  pkgs,
  inputs,
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

    # Install pi-plugins from the locked flake input.
    # Override in your target to use a local checkout during development:
    #   myConfig.pi.pluginsSource = /home/you/src/pi-plugins;
    myConfig.pi.pluginsSource = lib.mkDefault inputs.pi-plugins.outPath;
    myConfig.pi.plugins = lib.mkDefault ["pi-plugin-yaks"];

    # Use mkDefault so opencode wins if both are enabled
    myConfig.llmClient = {
      serverHost = lib.mkDefault "127.0.0.1";
      serverPort = lib.mkDefault "8080";
    };

    # Auto-configure bifrost as a model provider
    myConfig.pi.models.bifrost = lib.mkDefault {
      name = "Bifrost AI Gateway";
      provider = "bifrost";
      modelId = "openai/gpt-4o";
      baseUrl = "http://${host}:${port}/v1";
    };

    # Auto-configure OpenCode Go built-in provider (API key from 1Password)
    # modelId left empty to signal built-in provider override -
    # preserves all built-in models while providing the API key
    myConfig.pi.models.opencode-go = lib.mkDefault {
      name = "OpenCode Go";
      provider = "opencode-go";
      modelId = "";
      onePasswordItem = "op://Opnix/OpenCode Go API/credential";
    };

    # Default global agent instructions — override per-machine with a direct assignment
    myConfig.pi.agentsMd = lib.mkDefault (builtins.readFile ../common/AGENTS.md);

    environment.variables = {
      PI_CODING_AGENT_DIR = "$HOME/.pi/agent";
    };

    environment.shellAliases = {
      llm-status = "curl http://${host}:${port}/status";
      pi-status = "ls -la ~/.pi/agent";
      pi-sessions = "ls -la ~/.pi/agent/sessions 2>/dev/null || echo 'No sessions yet'";
      pi-config = "cat ~/.pi/agent/settings.json 2>/dev/null || echo 'No settings file'";
    };
    # RTK integration is handled by modules/home-manager/pi-coding-agent.nix
  };
}
