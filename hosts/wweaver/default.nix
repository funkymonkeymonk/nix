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

      # Work-specific role beyond the workstation archetype
      roles.opencode.enable = true;

      pi.pluginsSource = lib.mkDefault (inputs.pi-plugins.outPath or null);

      vane = {
        enable = true;
        autoStart = true;
        defaultModel = "qwen3.5";
        embeddingModel = "nomic-embed-text";
      };
      opencode = {
        enable = true;
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
