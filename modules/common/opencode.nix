# myConfig.opencode options — owned here, consumed by
# modules/home-manager/opencode.nix (loaded conditionally via
# modules/common/users.nix) and set by modules/roles/opencode.nix.
{lib, ...}: {
  options.myConfig.opencode = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable opencode user configuration management";
    };

    model = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Default LLM model for opencode (null means no default, user selects on first run)";
    };

    theme = lib.mkOption {
      type = lib.types.str;
      default = "system";
      description = "UI theme for opencode";
    };

    autoupdate = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable automatic updates for opencode";
    };

    agentsMd = lib.mkOption {
      type = lib.types.lines;
      default = "";
      description = ''
        Global AGENTS.md content installed to ~/.config/opencode/AGENTS.md.
        Loaded at startup by OpenCode as global agent instructions.
        Mirrors the pi agentsMd pattern.
      '';
    };

    enableBrowserAgents = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable browser automation agents (chrome-devtools, puppeteer-mcp). These agents are only loaded when explicitly invoked to minimize context usage.";
    };

    extraMcpServers = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule {
        options = {
          type = lib.mkOption {
            type = lib.types.enum ["local" "remote"];
            description = "Type of MCP server";
          };
          command = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [];
            description = "Command to run for local MCP servers";
          };
          url = lib.mkOption {
            type = lib.types.str;
            default = "";
            description = "URL for remote MCP servers";
          };
          enabled = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Whether this MCP server is enabled";
          };
        };
      });
      default = {};
      description = "Additional MCP servers to configure (merged with base devenv MCP server)";
    };

    disabledProviders = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "List of built-in provider names to disable (e.g., [\"opencode\" \"anthropic\"])";
    };

    providers = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule {
        options = {
          npm = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "NPM package for the provider (optional, e.g., @ai-sdk/openai-compatible)";
          };
          apiKey = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "Static API key for the provider (optional; prefer onePasswordItem for secrets)";
          };
          name = lib.mkOption {
            type = lib.types.str;
            description = "Display name of the provider";
          };
          baseURL = lib.mkOption {
            type = lib.types.str;
            default = "";
            description = "Base URL for the provider API. Can be empty when baseURLOpnixItem is set.";
          };
          models = lib.mkOption {
            type = lib.types.attrsOf (lib.types.submodule {
              options = {
                name = lib.mkOption {
                  type = lib.types.str;
                  description = "Display name of the model";
                };
              };
            });
            default = {};
            description = "Available models for this provider";
          };

          dynamicModels = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Fetch available models from the provider's /v1/models endpoint at runtime (useful for LiteLLM proxies)";
          };

          onePasswordItem = lib.mkOption {
            type = lib.types.str;
            default = "";
            description = "1Password item reference (e.g., 'op://vault/item/field') to retrieve API key from 1Password CLI";
          };

          baseURLOpnixItem = lib.mkOption {
            type = lib.types.str;
            default = "";
            description = "1Password item reference (e.g., 'op://vault/item/field') to retrieve the base URL. When set, baseURL can be left empty.";
          };
        };
      });
      default = {};
      description = "LLM providers configuration";
    };

    commands = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule {
        options = {
          template = lib.mkOption {
            type = lib.types.str;
            description = "The prompt template for the command";
          };
          description = lib.mkOption {
            type = lib.types.str;
            default = "";
            description = "Description shown in the TUI";
          };
          agent = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "Agent to use for this command";
          };
          subtask = lib.mkOption {
            type = lib.types.nullOr lib.types.bool;
            default = null;
            description = "Force command to run as subtask";
          };
          model = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "Override model for this command";
          };
        };
      });
      default = {};
      description = "Custom opencode commands (slash commands)";
    };

    agents = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule {
        options = {
          description = lib.mkOption {
            type = lib.types.str;
            default = "";
            description = "Description of what the agent does";
          };
          mode = lib.mkOption {
            type = lib.types.enum ["primary" "subagent" "all"];
            default = "primary";
            description = "Agent mode: primary (switchable), subagent (@mention), or all";
          };
          model = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "Model for this agent (e.g., omlx/qwen3.8-27b)";
          };
          prompt = lib.mkOption {
            type = lib.types.str;
            default = "";
            description = "System prompt for the agent";
          };
          temperature = lib.mkOption {
            type = lib.types.nullOr lib.types.float;
            default = null;
            description = "Temperature for the agent (0.0-1.0)";
          };
          hidden = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Hide from autocomplete menu";
          };
          tools = lib.mkOption {
            type = lib.types.attrsOf lib.types.bool;
            default = {};
            description = "Tool permissions for this agent";
          };
          permission = lib.mkOption {
            type = lib.types.attrsOf (lib.types.oneOf [lib.types.str (lib.types.attrsOf lib.types.str)]);
            default = {};
            description = "Permission settings for this agent";
          };
          color = lib.mkOption {
            type = lib.types.str;
            default = "";
            description = "Agent color in UI (hex or theme color name)";
          };
        };
      });
      default = {};
      description = "Custom agents for OpenCode";
    };
  };
}
