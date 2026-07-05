# wweaver — work laptop (Will Weaver)
# Thin host file — imports workstation archetype, adds work-specific config
# (Justworks providers, vane with LiteLLM, opencode agents/commands, etc.)
{
  mkUser,
  inputs,
  ...
}: {
  nixpkgs.hostPlatform = "aarch64-darwin";
  system.stateVersion = 4;
  system.primaryUser = "wweaver";

  homebrew.casks = [
    "granola"
  ];

  imports = [
    ../../library/archetypes/workstation-darwin.nix
  ];

  myConfig =
    mkUser "wweaver" "wweaver@justworks.com"
    // {
      skills = {
        superpowersPath = inputs.superpowers;
        externalInputs = {
          inherit (inputs) vercel-skills;
        };
      };
      onepassword.sudoPasswordRef = "op://Employee/wweaver Sudo Password/password";

      # Extra roles beyond workstation archetype
      roles.entertainment.enable = true;
      roles.llm-host.enable = true;
      roles.opencode.enable = true;

      vane = {
        enable = true;
        autoStart = true;
        ollamaUrl = "http://host.docker.internal:11434";
        openaiBaseUrlOpnixItem = "op://Justworks/LiteLLM/baseURL";
        embeddedSearxng = true;
        defaultModel = "qwen3.5";
        embeddingModel = "nomic-embed-text";
        colima = {
          cpu = 6;
          memory = 12;
          disk = 60;
        };
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
          workspace = {
            description = "Create a jj workspace for isolated work with fast sync enabled";
            template = ''
              Create a jj workspace session for isolated development work.

              Run this command:
              ```bash
              jj-workspace-session start $ARGUMENTS
              ```

              Then report the workspace name and path to the user, and cd into the workspace directory.

              If no arguments provided, this starts session tracking in the current workspace.
              If a name is provided (e.g., "feat/auth" or "fix/bug"), it creates a new workspace.
              A second argument can specify the base branch (defaults to main).

              Examples:
              - /workspace feat/user-auth      -> Creates feat/user-auth-<date>-<id> from main
              - /workspace fix/bug develop     -> Creates fix/bug-<date>-<id> from develop
              - /workspace                     -> Starts session in current workspace
            '';
          };
        };
        providers = {
          just-llms = {
            npm = "@ai-sdk/openai-compatible";
            name = "Just LLMs";
            baseURL = "";
            baseURLOpnixItem = "op://Justworks/LiteLLM/baseURL";
            onePasswordItem = "op://Justworks/Justworks LiteLLM/wweaver-poweruser-key";
            dynamicModels = true;
            models = {
              "us.anthropic.claude-opus-4-5-20251101-v1:0" = {
                name = "Claude Opus 4.5 (Bedrock)";
              };
            };
          };
          ollama = {
            npm = "@ai-sdk/openai-compatible";
            name = "Ollama (local)";
            baseURL = "http://localhost:11434/v1";
            models = {
              "qwen3.5:latest" = {name = "Qwen 3.5 (7B)";};
              "qwen3.5:2b" = {name = "Qwen 3.5 (2B)";};
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
