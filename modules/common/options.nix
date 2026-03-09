{
  config,
  lib,
  ...
}:
with lib; {
  options.myConfig = {
    # Computed helper for platform detection (read-only)
    isDarwin = mkOption {
      type = types.bool;
      default = builtins.elem config.nixpkgs.hostPlatform.system ["aarch64-darwin" "x86_64-darwin"];
      readOnly = true;
      description = "Whether the current system is Darwin (macOS)";
    };

    users = mkOption {
      type = types.listOf (types.submodule {
        options = {
          name = mkOption {
            type = types.str;
            description = "Username for the user account";
          };
          email = mkOption {
            type = types.str;
            description = "Email address for the user";
          };
          fullName = mkOption {
            type = types.str;
            default = "";
            description = "Full name of the user";
          };
          isAdmin = mkOption {
            type = types.bool;
            default = true;
            description = "Whether the user should have admin privileges";
          };
          sshIncludes = mkOption {
            type = types.listOf types.str;
            default = [];
            description = "Additional SSH config files to include";
          };
        };
      });
      default = [];
      description = "List of users to configure on the system";
    };

    development = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Enable development tools and environment";
      };
    };

    agent-skills = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Enable agent skills management";
      };
    };

    skills = {
      enabledRoles = mkOption {
        type = types.listOf types.str;
        default = [];
        description = "List of enabled roles for skills filtering (set automatically by bundle configuration)";
      };

      skillsPath = mkOption {
        type = types.str;
        default = ".config/opencode/skills";
        description = "Path relative to home directory where skills are installed";
      };

      superpowersPath = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = "Path to the superpowers flake input (set automatically from flake inputs)";
      };
    };

    opencode = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Enable opencode user configuration management";
      };

      model = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Default LLM model for opencode (null means no default, user selects on first run)";
      };

      theme = mkOption {
        type = types.str;
        default = "opencode";
        description = "UI theme for opencode";
      };

      autoupdate = mkOption {
        type = types.bool;
        default = true;
        description = "Enable automatic updates for opencode";
      };

      enableBrowserAgents = mkOption {
        type = types.bool;
        default = false;
        description = "Enable browser automation agents (chrome-devtools, puppeteer-mcp). These agents are only loaded when explicitly invoked to minimize context usage.";
      };

      extraMcpServers = mkOption {
        type = types.attrsOf (types.submodule {
          options = {
            type = mkOption {
              type = types.enum ["local" "remote"];
              description = "Type of MCP server";
            };
            command = mkOption {
              type = types.listOf types.str;
              default = [];
              description = "Command to run for local MCP servers";
            };
            url = mkOption {
              type = types.str;
              default = "";
              description = "URL for remote MCP servers";
            };
            enabled = mkOption {
              type = types.bool;
              default = true;
              description = "Whether this MCP server is enabled";
            };
          };
        });
        default = {};
        description = "Additional MCP servers to configure (merged with base devenv MCP server)";
      };

      disabledProviders = mkOption {
        type = types.listOf types.str;
        default = [];
        description = "List of built-in provider names to disable (e.g., [\"opencode\" \"anthropic\"])";
      };

      providers = mkOption {
        type = types.attrsOf (types.submodule {
          options = {
            npm = mkOption {
              type = types.nullOr types.str;
              default = null;
              description = "NPM package for the provider (optional, e.g., @ai-sdk/openai-compatible)";
            };
            name = mkOption {
              type = types.str;
              description = "Display name of the provider";
            };
            baseURL = mkOption {
              type = types.str;
              description = "Base URL for the provider API";
            };
            models = mkOption {
              type = types.attrsOf (types.submodule {
                options = {
                  name = mkOption {
                    type = types.str;
                    description = "Display name of the model";
                  };
                };
              });
              default = {};
              description = "Available models for this provider";
            };

            onePasswordItem = mkOption {
              type = types.str;
              default = "";
              description = "1Password item reference (e.g., 'op://vault/item/field') to retrieve API key from 1Password CLI";
            };
          };
        });
        default = {};
        description = "LLM providers configuration";
      };

      commands = mkOption {
        type = types.attrsOf (types.submodule {
          options = {
            template = mkOption {
              type = types.str;
              description = "The prompt template for the command";
            };
            description = mkOption {
              type = types.str;
              default = "";
              description = "Description shown in the TUI";
            };
            agent = mkOption {
              type = types.nullOr types.str;
              default = null;
              description = "Agent to use for this command";
            };
            subtask = mkOption {
              type = types.nullOr types.bool;
              default = null;
              description = "Force command to run as subtask";
            };
            model = mkOption {
              type = types.nullOr types.str;
              default = null;
              description = "Override model for this command";
            };
          };
        });
        default = {};
        description = "Custom opencode commands (slash commands)";
      };

      agents = mkOption {
        type = types.attrsOf (types.submodule {
          options = {
            description = mkOption {
              type = types.str;
              default = "";
              description = "Description of what the agent does";
            };
            mode = mkOption {
              type = types.enum ["primary" "subagent" "all"];
              default = "primary";
              description = "Agent mode: primary (switchable), subagent (@mention), or all";
            };
            model = mkOption {
              type = types.nullOr types.str;
              default = null;
              description = "Model for this agent (e.g., ollama/qwen3.5:2b)";
            };
            prompt = mkOption {
              type = types.str;
              default = "";
              description = "System prompt for the agent";
            };
            temperature = mkOption {
              type = types.nullOr types.float;
              default = null;
              description = "Temperature for the agent (0.0-1.0)";
            };
            hidden = mkOption {
              type = types.bool;
              default = false;
              description = "Hide from autocomplete menu";
            };
            tools = mkOption {
              type = types.attrsOf types.bool;
              default = {};
              description = "Tool permissions for this agent";
            };
            permission = mkOption {
              type = types.attrsOf (types.oneOf [types.str (types.attrsOf types.str)]);
              default = {};
              description = "Permission settings for this agent";
            };
            color = mkOption {
              type = types.str;
              default = "";
              description = "Agent color in UI (hex or theme color name)";
            };
          };
        });
        default = {};
        description = "Custom agents for OpenCode";
      };
    };

    onepassword = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Enable 1Password integration";
      };

      enableGUI = mkOption {
        type = types.bool;
        default = true;
        description = "Enable 1Password GUI application";
      };

      enableSSHAgent = mkOption {
        type = types.bool;
        default = true;
        description = "Enable 1Password SSH agent";
      };

      enableGitSigning = mkOption {
        type = types.bool;
        default = true;
        description = "Enable git commit signing with 1Password";
      };

      signingKey = mkOption {
        type = types.str;
        default = "";
        description = "SSH key name for git signing in 1Password";
      };
    };

    zellij = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Enable zellij terminal multiplexer configuration";
      };
    };

    ollama = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Enable Ollama local LLM service";
      };

      host = mkOption {
        type = types.str;
        default = "127.0.0.1";
        description = "Host address for Ollama to bind to (use 0.0.0.0 for network access)";
      };

      port = mkOption {
        type = types.port;
        default = 11434;
        description = "Port for Ollama API";
      };

      models = mkOption {
        type = types.listOf types.str;
        default = [];
        description = "List of models to pre-pull on service start";
      };

      acceleration = mkOption {
        type = types.nullOr (types.enum ["cuda" "rocm" "metal"]);
        default = null;
        description = "GPU acceleration type (null for auto-detection)";
      };

      environmentFile = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = "Path to environment file with additional Ollama configuration";
      };

      useHomebrew = mkOption {
        type = types.bool;
        default = false;
        description = "Use Homebrew-installed Ollama instead of Nix package (Darwin only). Useful for getting the latest version with Metal acceleration";
      };
    };

    sharedModels = mkOption {
      type = types.listOf types.str;
      default = ["qwen3:4b" "gemma3:4b" "qwen3.5"];
      description = "Central model configuration - change here to affect ALL Ollama services and instances.\n\nRecommended models:\n  qwen3:4b     - Research/Analysis\n  gemma3:4b    - Chat (fast responses)\n  qwen3.5      - Coding/Planning (best model)\n  qwen2.5-coder:7b - Coding alternatives\n  llama3.2     - Lightweight fallback";
    };

    llmEndpoints = mkOption {
      type = types.attrsOf (types.submodule {
        options = {
          host = mkOption {
            type = types.str;
            description = "Host address for the LLM endpoint";
          };
          port = mkOption {
            type = types.str;
            description = "Port for the LLM endpoint";
          };
        };
      });
      default = {};
      description = "Additional LLM endpoint configurations (merged with default localhost endpoint)";
    };

    llmClient = {
      serverHost = mkOption {
        type = types.str;
        default = "127.0.0.1";
        description = "Default LLM server host for client tools";
      };

      serverPort = mkOption {
        type = types.str;
        default = "11434";
        description = "Default LLM server port for client tools";
      };
    };

    jj-autosync = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Enable automatic jj repository synchronization";
      };

      username = mkOption {
        type = types.str;
        default = "";
        description = "Username for launchd environment (required on Darwin)";
      };

      reposDir = mkOption {
        type = types.str;
        default = "$HOME/repos";
        description = "Directory containing jj repositories to sync";
      };

      mainBranch = mkOption {
        type = types.str;
        default = "main";
        description = "Main branch name to sync";
      };

      hourlySync = mkOption {
        type = types.bool;
        default = true;
        description = "Enable hourly background sync for all repos";
      };

      fastSyncInterval = mkOption {
        type = types.int;
        default = 300;
        description = "Sync interval in seconds for active sessions (default: 300 = 5 minutes)";
      };

      sessionTtlSeconds = mkOption {
        type = types.int;
        default = 1800;
        description = "Session TTL in seconds before auto-expiry (default: 1800 = 30 minutes). TTL resets on each sync.";
      };
    };

    claude-code = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Enable Claude Code configuration management";
      };

      includeCoAuthoredBy = mkOption {
        type = types.bool;
        default = false;
        description = "Whether to include Co-Authored-By trailers in commits";
      };

      extraSettings = mkOption {
        type = types.attrs;
        default = {};
        description = "Additional Claude Code settings";
      };

      mcpServers = mkOption {
        type = types.attrsOf (types.submodule {
          options = {
            type = mkOption {
              type = types.enum ["local" "remote"];
              description = "Type of MCP server";
            };
            command = mkOption {
              type = types.listOf types.str;
              default = [];
              description = "Command to run for local MCP servers";
            };
            url = mkOption {
              type = types.str;
              default = "";
              description = "URL for remote MCP servers";
            };
            enabled = mkOption {
              type = types.bool;
              default = true;
              description = "Whether this MCP server is enabled";
            };
            apiKey = mkOption {
              type = types.str;
              default = "";
              description = "API key for the MCP server (use onePasswordItem instead for secrets)";
            };
            onePasswordItem = mkOption {
              type = types.str;
              default = "";
              description = "1Password item reference (e.g., 'op://vault/item/field') to retrieve API key";
            };
          };
        });
        default = {};
        description = "MCP servers configuration for Claude Code";
      };

      agents = mkOption {
        type = types.attrsOf types.str;
        default = {};
        description = "Custom agents for Claude Code";
      };

      commands = mkOption {
        type = types.attrsOf types.str;
        default = {};
        description = "Custom commands for Claude Code";
      };

      hooks = mkOption {
        type = types.attrsOf types.str;
        default = {};
        description = "Custom hooks for Claude Code";
      };

      rtk = {
        enable = mkOption {
          type = types.bool;
          default = false;
          description = "Enable RTK (Rust Token Killer) hook for Claude Code";
        };
      };
    };
  };
}
