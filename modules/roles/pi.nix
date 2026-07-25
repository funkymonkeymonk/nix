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

    # Default plugin selection. pluginsSource (the flake input providing these
    # plugins) is set at the composition point (archetype/host), not here —
    # mirrors how myConfig.skills.superpowersPath is wired, since a role module
    # should not need `inputs` directly. Override per-machine with a direct
    # assignment.
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
      modelId = "gemma4:26b";
      baseUrl = "http://${host}:${port}/v1";
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
