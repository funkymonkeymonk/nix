# wweaver — work laptop (Will Weaver)
# Machine-specific overrides on top of workstation-darwin archetype.
{
  mkUser,
  inputs,
  lib,
  ...
}: {
  imports = [
    ../../library/archetypes/workstation-darwin.nix
  ];

  nixpkgs.hostPlatform = "aarch64-darwin";
  system.stateVersion = 4;
  system.primaryUser = "wweaver";

  homebrew.casks = [
    "granola"
  ];

  myConfig =
    mkUser "wweaver" "wweaver@justworks.com"
    // {
      skills = {
        externalInputs = {
          inherit (inputs) vercel-skills;
        };
      };
      onepassword.sudoPasswordRef = "op://Employee/wweaver Sudo Password/password";

      obsidian.vaults = ["personal"];

      # Local Qwen 3.8 inference through oMLX.
      omlx = {
        enable = true;
        server = {
          host = "0.0.0.0";
          port = 8300;
        };
        memoryGuardGb = 32;
        maxConcurrentRequests = 4;
        hotCacheMaxSize = "8GB";
      };

      # Work-specific roles beyond the workstation archetype
      roles.opencode.enable = true;
      roles.work.enable = true;

      pi.pluginsSource = lib.mkDefault (inputs.pi-plugins.outPath or null);

      pi.npmPackages = {
        # Subagent dispatch tool (scout/researcher/worker/reviewer/oracle)
        # for pi, mirroring opencode/claude's native Task tool / @mention
        # subagent support — needed by dispatching-parallel-agents and
        # subagent-driven-development skills.
        "pi-subagents" = "^0.51.0";
      };

      bifrost = {
        enable = true;
        upstreams.omlx = {
          url = "http://localhost:8300";
          type = "openai";
          requestTimeout = 600;
          streamIdleTimeoutInSeconds = 600;
          models = ["qwen3.8-27b"];
        };
      };
      opencode = {
        enable = true;
        disabledProviders = ["opencode"];
        model = "local-bifrost/omlx/qwen3.8-27b";
        commands = {
          diataxis = {
            description = "Audit and rewrite documentation using the Diataxis framework";
            template = ''
              Load the diataxis-docs skill and use it to audit and restructure the documentation in this project.

              Follow the Diataxis framework to organize content into:
              - Tutorials (learning-oriented)
              - How-to guides (goal-oriented)
              - Reference (information-oriented)
              - Explanation (understanding-oriented)

              $ARGUMENTS
            '';
          };
        };
        providers = {};
      };
      claude-code = {
        enable = false;
        mcpServers = {
          github = {
            type = "remote";
            url = "https://api.githubcopilot.com/mcp/";
            enabled = true;
          };
          jira = {
            type = "remote";
            url = "https://mcp.atlassian.com/v1/mcp";
            enabled = false;
          };
          confluence = {
            type = "remote";
            url = "https://mcp.atlassian.com/v1/mcp";
            enabled = false;
          };
        };
      };
    };
}
