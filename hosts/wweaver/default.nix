# wweaver — work laptop (Will Weaver)
# Machine-specific overrides only — developer-laptop-darwin archetype provides
# the base (homebrew, desktop, entertainment roles, superpowersPath).
# Hardware-specific: vane colima sizing, onepassword.sudoPasswordRef.
# User preference: opencode providers, commands, MCP servers → profile data here.
{
  mkUser,
  inputs,
  lib,
  ...
}: {
  imports = [
    ../../library/archetypes/developer-laptop-darwin.nix
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

      # Roles beyond developer-laptop-darwin archetype (homebrew, desktop, entertainment already set)
      roles.developer.enable = true;
      roles.workstation.enable = true;
      roles.opencode.enable = true;
      roles.pi.enable = true;

      pi.pluginsSource = lib.mkDefault (inputs.pi-plugins.outPath or null);

      vane = {
        enable = true;
        autoStart = true;
        openaiBaseUrl = "https://litellm.justworksai.net/v1";
        defaultModel = "qwen3.5";
        embeddingModel = "nomic-embed-text";
      };
      opencode = {
        model = "just-llms/claude-sonnet-4-6";
        disabledProviders = ["opencode"];
        extraMcpServers = {
          github = {
            type = "remote";
            url = "https://api.githubcopilot.com/mcp/";
            enabled = false;
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
        providers = {
          just-llms = {
            npm = "@ai-sdk/openai-compatible";
            name = "Just LLMs";
            baseURL = "https://litellm.justworksai.net/v1";
            onePasswordItem = "op://Justworks/Justworks LiteLLM/wweaver-poweruser-key";
            dynamicModels = true;
            models = {
              "us.anthropic.claude-opus-4-5-20251101-v1:0" = {
                name = "Claude Opus 4.5 (Bedrock)";
              };
            };
          };
        };
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
