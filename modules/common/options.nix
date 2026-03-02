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
              type = types.str;
              description = "NPM package for the provider";
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
        default = ["llama3.2" "codellama"];
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
    };

    postgresql = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Enable PostgreSQL database server";
      };

      port = mkOption {
        type = types.port;
        default = 5432;
        description = "Port for PostgreSQL to listen on";
      };

      enableTCPIP = mkOption {
        type = types.bool;
        default = false;
        description = "Whether PostgreSQL should listen on all network interfaces";
      };

      databases = mkOption {
        type = types.listOf types.str;
        default = [];
        description = "List of databases to create";
      };

      users = mkOption {
        type = types.listOf (types.submodule {
          options = {
            name = mkOption {
              type = types.str;
              description = "Username for the PostgreSQL user";
            };
            ensureDBOwnership = mkOption {
              type = types.bool;
              default = false;
              description = "Whether to grant ownership of a database with the same name";
            };
          };
        });
        default = [];
        description = "List of PostgreSQL users to create";
      };

      dataDir = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Custom data directory for PostgreSQL (null uses default)";
      };

      package = mkOption {
        type = types.nullOr types.package;
        default = null;
        description = "PostgreSQL package to use (null uses default)";
      };
    };

    litellm = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Enable LiteLLM proxy server";
      };

      host = mkOption {
        type = types.str;
        default = "0.0.0.0";
        description = "Host address for LiteLLM to bind to";
      };

      port = mkOption {
        type = types.port;
        default = 4000;
        description = "Port for LiteLLM API (OpenAI-compatible)";
      };

      configFile = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = "Path to LiteLLM config.yaml file";
      };

      masterKey = mkOption {
        type = types.str;
        default = "";
        description = "Master API key for LiteLLM (leave empty to use 1Password)";
      };

      masterKeyOnePassword = mkOption {
        type = types.str;
        default = "";
        description = "1Password item reference for master key (e.g., 'op://vault/item/field')";
      };

      saltKey = mkOption {
        type = types.str;
        default = "";
        description = "Salt key for encrypting credentials in DB (CANNOT CHANGE once set)";
      };

      saltKeyOnePassword = mkOption {
        type = types.str;
        default = "";
        description = "1Password item reference for salt key";
      };

      databaseUrl = mkOption {
        type = types.str;
        default = "";
        description = "PostgreSQL database URL for storing model credentials";
      };

      databaseUrlOnePassword = mkOption {
        type = types.str;
        default = "";
        description = "1Password item reference for database URL";
      };

      ollamaBaseUrl = mkOption {
        type = types.str;
        default = "http://localhost:11434";
        description = "Base URL for local Ollama instance";
      };

      anthropicApiKey = mkOption {
        type = types.str;
        default = "";
        description = "Anthropic API key (leave empty to use 1Password)";
      };

      anthropicApiKeyOnePassword = mkOption {
        type = types.str;
        default = "";
        description = "1Password item reference for Anthropic API key";
      };

      openaiApiKey = mkOption {
        type = types.str;
        default = "";
        description = "OpenAI API key (leave empty to use 1Password)";
      };

      openaiApiKeyOnePassword = mkOption {
        type = types.str;
        default = "";
        description = "1Password item reference for OpenAI API key";
      };

      extraProviders = mkOption {
        type = types.attrsOf (types.submodule {
          options = {
            apiBase = mkOption {
              type = types.str;
              description = "Base URL for the provider API";
            };
            apiKey = mkOption {
              type = types.str;
              default = "";
              description = "API key (leave empty to use 1Password)";
            };
            apiKeyOnePassword = mkOption {
              type = types.str;
              default = "";
              description = "1Password item reference for API key";
            };
          };
        });
        default = {};
        description = "Additional LLM providers to configure";
      };

      models = mkOption {
        type = types.listOf (types.submodule {
          options = {
            modelName = mkOption {
              type = types.str;
              description = "Name to expose via LiteLLM API";
            };
            litellmParams = mkOption {
              type = types.submodule {
                options = {
                  model = mkOption {
                    type = types.str;
                    description = "Provider model identifier (e.g., 'ollama/llama3.2', 'claude-3-opus')";
                  };
                  apiBase = mkOption {
                    type = types.nullOr types.str;
                    default = null;
                    description = "Override API base URL for this model";
                  };
                };
              };
              description = "LiteLLM model parameters";
            };
          };
        });
        default = [];
        description = "List of models to expose through LiteLLM";
      };

      logLevel = mkOption {
        type = types.enum ["DEBUG" "INFO" "WARNING" "ERROR"];
        default = "INFO";
        description = "Log level for LiteLLM";
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
