{
  config,
  lib,
  pkgs,
  ...
}:
with lib; {
  options.myConfig = {
    # Computed helper for platform detection (read-only)
    # Uses _module.args.pkgs which is always available during module evaluation
    isDarwin = mkOption {
      type = types.bool;
      default = builtins.elem pkgs.stdenv.hostPlatform.system ["aarch64-darwin" "x86_64-darwin"];
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

    # Role toggles — each corresponds to a module in modules/roles/
    roles = {
      foundation = {
        enable = mkOption {
          type = types.bool;
          default = true;
          description = "Foundation role — always-on base tools (1Password CLI, git, helix, zsh, etc.)";
        };
      };
      developer = {
        enable = mkOption {
          type = types.bool;
          default = false;
          description = "Development tools (clang, python, node, k8s, gh-dash)";
        };
      };
      creative = {
        enable = mkOption {
          type = types.bool;
          default = false;
          description = "Media tools (ffmpeg, imagemagick, pandoc)";
        };
      };
      gaming = {
        enable = mkOption {
          type = types.bool;
          default = false;
          description = "Gaming tools (moonlight-qt)";
        };
      };
      desktop = {
        enable = mkOption {
          type = types.bool;
          default = false;
          description = "Desktop applications (logseq, super-productivity, element)";
        };
      };
      workstation = {
        enable = mkOption {
          type = types.bool;
          default = false;
          description = "Work tools (slack, trippy, unar)";
        };
      };
      entertainment = {
        enable = mkOption {
          type = types.bool;
          default = false;
          description = "Entertainment apps — macOS homebrew casks (steam, obs, discord)";
        };
      };
      agent-skills = {
        enable = mkOption {
          type = types.bool;
          default = false;
          description = "AI agent skills management (auto-enabled by opencode/claude)";
        };
      };
      opencode = {
        enable = mkOption {
          type = types.bool;
          default = false;
          description = "OpenCode AI assistant with rtk";
        };
      };
      claude = {
        enable = mkOption {
          type = types.bool;
          default = false;
          description = "Claude Code AI assistant with rtk";
        };
      };
      pi = {
        enable = mkOption {
          type = types.bool;
          default = false;
          description = "Pi coding agent with rtk";
        };
      };
      llm-host = {
        enable = mkOption {
          type = types.bool;
          default = false;
          description = "Local LLM hosting (ollama)";
        };
      };
      microvm-host = {
        enable = mkOption {
          type = types.bool;
          default = false;
          description = "MicroVM host infrastructure (bridge networking, DNS/connection logging, cloud-init VM discovery)";
        };
      };
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

      externalInputs = mkOption {
        type = types.attrsOf types.path;
        default = {};
        description = "Attribute set of external skill repository flake inputs (e.g., vercel-skills = inputs.vercel-skills)";
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
        default = "system";
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

            dynamicModels = mkOption {
              type = types.bool;
              default = false;
              description = "Fetch available models from the provider's /v1/models endpoint at runtime (useful for LiteLLM proxies)";
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
        default = true;
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

      enableSudo = mkOption {
        type = types.bool;
        default = true;
        description = "Enable 1Password for sudo authentication (NixOS only)";
      };

      tokenFile = mkOption {
        type = types.path;
        default = "/etc/opnix-token";
        description = ''
          Path to the 1Password service account token file.
          This file should contain a 1Password service account token and have restricted permissions (0600).
          The token is used by opnix to fetch secrets at runtime.

          To create a service account token:
          1. Go to https://my.1password.com/developer-tools/service-accounts
          2. Create a service account with access to the vaults containing your secrets
          3. Copy the token and save it to this file

          The service will fail gracefully if the token file doesn't exist or is invalid.
        '';
      };

      secrets = mkOption {
        type = types.attrsOf (types.submodule {
          options = {
            reference = mkOption {
              type = types.str;
              description = "1Password reference (e.g., 'op://vault/item/field')";
            };
            path = mkOption {
              type = types.nullOr types.str;
              default = null;
              description = ''
                Path where the secret should be written.
                If null, opnix uses its outputDir (default: /var/lib/opnix/secrets) plus the secret name.
              '';
            };
            mode = mkOption {
              type = types.str;
              default = "0600";
              description = "File permissions for the secret";
            };
            owner = mkOption {
              type = types.str;
              default = "root";
              description = "Owner of the secret file";
            };
            group = mkOption {
              type = types.str;
              default = "root";
              description = "Group of the secret file";
            };
            services = mkOption {
              type = types.listOf types.str;
              default = [];
              description = "Services that depend on this secret (will be restarted when secret changes)";
            };
          };
        });
        default = {};
        description = ''
          Secrets to fetch from 1Password using opnix.
          Secrets are fetched at boot time and written to the specified paths.
          The 1Password service account must have access to the referenced vaults.

          Example:
          {
            myApiKey = {
              reference = "op://Private/MyAPI/credential";
              path = "/run/secrets/my-api-key";
              mode = "0600";
              owner = "myuser";
            };
          }
        '';
      };
    };

    syncthing = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Enable Syncthing file synchronization";
      };
    };

    charm = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enable Charm CLI tools configuration (glow markdown renderer, mods AI CLI)";
      };

      glow = {
        style = mkOption {
          type = types.str;
          default = "auto";
          description = ''
            Glow rendering style. "auto" detects the terminal background and
            picks "dark" or "light". Can also be a path to a custom JSON
            stylesheet (see glamour style gallery).
          '';
        };

        width = mkOption {
          type = types.int;
          default = 140;
          description = "Word-wrap width for glow output (0 to disable wrapping)";
        };

        pager = mkOption {
          type = types.bool;
          default = false;
          description = "Display output in a pager (like less -r)";
        };

        mouse = mkOption {
          type = types.bool;
          default = false;
          description = "Enable mouse wheel support in TUI mode";
        };

        showLineNumbers = mkOption {
          type = types.bool;
          default = false;
          description = "Show line numbers in TUI mode";
        };

        preserveNewLines = mkOption {
          type = types.bool;
          default = false;
          description = "Preserve newlines in rendered output";
        };
      };

      mods = {
        enable = mkOption {
          type = types.bool;
          default = false;
          description = "Enable mods (AI on the command line) from Charm";
        };

        settings = mkOption {
          type = types.attrs;
          default = {};
          description = ''
            Mods configuration written to $XDG_CONFIG_HOME/mods/mods.yml.
            See https://github.com/charmbracelet/mods for available options.
          '';
        };
      };
    };

    zellij = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Enable zellij terminal multiplexer configuration";
      };
    };

    fjj = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Enable fjj (Fast Jujutsu Workflow) for multi-agent repository management with GitHub mirrors and isolated workspaces";
      };

      mirrorRoot = mkOption {
        type = types.str;
        default =
          if config.myConfig.isDarwin
          then "~/src"
          else "/srv/github";
        description = "Root directory for GitHub repository mirrors (always on main branch). Default is ~/src on Darwin, /srv/github on Linux. Mirrors stored as <mirrorRoot>/github/<owner>/<repo>";
      };

      workspaceRoot = mkOption {
        type = types.str;
        default = "~/workspaces";
        description = "Root directory for per-agent workspaces";
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

    vane = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Enable Vane (AI-powered answering engine with web search, formerly Perplexica)";
      };

      port = mkOption {
        type = types.port;
        default = 3000;
        description = "Port for Vane web UI";
      };

      dataDir = mkOption {
        type = types.str;
        default = "$HOME/.local/share/vane";
        description = "Directory for Vane data and configuration";
      };

      ollamaUrl = mkOption {
        type = types.nullOr types.str;
        default = "http://host.docker.internal:11434";
        description = "URL for Ollama API. For Docker on macOS, use host.docker.internal";
      };

      embeddedSearxng = mkOption {
        type = types.bool;
        default = true;
        description = "Run embedded SearxNG instance for web search. Disable if using external SearxNG";
      };

      searxngUrl = mkOption {
        type = types.str;
        default = "http://searxng:8080";
        description = "URL for SearxNG API. Use 'http://searxng:8080' for embedded, or external URL";
      };

      searxngPort = mkOption {
        type = types.port;
        default = 8080;
        description = "Port for embedded SearxNG (only used if embeddedSearxng is true)";
      };

      embeddedOllama = mkOption {
        type = types.bool;
        default = false;
        description = "Run embedded Ollama instance in Docker. Enable for self-contained setup without external Ollama";
      };

      ollamaContainerPort = mkOption {
        type = types.port;
        default = 11434;
        description = "Host port for embedded Ollama container (only used if embeddedOllama is true)";
      };

      openaiApiKey = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "OpenAI API key for using OpenAI models (optional)";
      };

      openaiBaseUrl = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Custom OpenAI-compatible API base URL (e.g., LiteLLM endpoint). Leave null for official OpenAI API.";
      };

      anthropicApiKey = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Anthropic API key for using Claude models (optional)";
      };

      extraEnvironment = mkOption {
        type = types.attrsOf types.str;
        default = {};
        description = "Additional environment variables for Vane containers";
      };

      defaultModel = mkOption {
        type = types.nullOr types.str;
        default = "deepseek-r1:14b";
        description = "Default Ollama chat model for Vane. Set to null to skip auto-configuration and configure manually via web UI.";
      };

      embeddingModel = mkOption {
        type = types.nullOr types.str;
        default = "nomic-embed-text";
        description = "Ollama embedding model for Vane vector search. Set to null to skip.";
      };

      autoStart = mkOption {
        type = types.bool;
        default = false;
        description = "Automatically start Vane service on login (recommended: false to avoid boot slowdown)";
      };

      colima = {
        cpu = mkOption {
          type = types.int;
          default = 4;
          description = "Number of CPU cores for Vane's dedicated Colima VM";
        };

        memory = mkOption {
          type = types.int;
          default = 8;
          description = "Memory in GB for Vane's dedicated Colima VM";
        };

        disk = mkOption {
          type = types.int;
          default = 60;
          description = "Disk space in GB for Vane's dedicated Colima VM";
        };
      };
    };

    cachix = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enable Cachix binary cache";
      };
    };

    autoUpgrade = {
      flakeUrl = mkOption {
        type = types.str;
        default = "";
        description = "GitHub flake URL for auto-upgrade (e.g., 'github:funkymonkeymonk/nix#type-server'). Set this to enable auto-upgrade on NixOS machines.";
      };
    };

    motd = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enable MOTD (Message of the Day) showing git commit info on shell login";
      };

      showGitCommit = mkOption {
        type = types.bool;
        default = true;
        description = "Show the git commit hash the system was built from";
      };

      showHostname = mkOption {
        type = types.bool;
        default = true;
        description = "Show the system hostname";
      };

      showSystem = mkOption {
        type = types.bool;
        default = true;
        description = "Show the operating system and architecture";
      };

      extraMessage = mkOption {
        type = types.str;
        default = "";
        description = "Additional custom message to display in MOTD";
      };

      githubUrl = mkOption {
        type = types.str;
        default = "https://github.com/funkymonkeymonk/nix";
        description = "GitHub repository URL for linking to commits in MOTD";
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

      rtk = {
        enable = mkOption {
          type = types.bool;
          default = false;
          description = "Enable RTK (Rust Token Killer) for token-optimized LLM tool output. Automatically integrates with OpenCode and Claude Code when their respective roles are enabled.";
        };
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
    };

    pi = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Enable pi coding agent configuration management";
      };

      settings = mkOption {
        type = types.attrs;
        default = {};
        description = ''
          Pi settings.json configuration.
          See https://github.com/badlogic/pi-mono/blob/main/packages/coding-agent/docs/settings.md
          for available options.
        '';
      };

      agentsMd = mkOption {
        type = types.lines;
        default = "";
        description = ''
          Global AGENTS.md content. This is loaded at startup from ~/.pi/agent/AGENTS.md
          and provides project-agnostic instructions to pi.
        '';
      };

      systemMd = mkOption {
        type = types.lines;
        default = "";
        description = ''
          Custom system prompt content. Written to ~/.pi/agent/SYSTEM.md.
          Replaces the default system prompt. Use APPEND_SYSTEM.md to append instead.
        '';
      };

      keybindings = mkOption {
        type = types.attrsOf types.str;
        default = {};
        description = ''
          Custom keybindings configuration.
          Keys are action names, values are key combinations.
          See https://github.com/badlogic/pi-mono/blob/main/packages/coding-agent/docs/keybindings.md
        '';
      };

      models = mkOption {
        type = types.attrsOf (types.submodule {
          options = {
            name = mkOption {
              type = types.str;
              description = "Display name for the model";
            };
            provider = mkOption {
              type = types.str;
              description = "Provider ID (e.g., 'anthropic', 'openai', 'ollama')";
            };
            modelId = mkOption {
              type = types.str;
              description = "Model identifier (e.g., 'claude-sonnet-4-6', 'gpt-4o')";
            };
            apiKey = mkOption {
              type = types.str;
              default = "";
              description = "API key for the model (use onePasswordItem for secrets)";
            };
            onePasswordItem = mkOption {
              type = types.str;
              default = "";
              description = "1Password item reference (e.g., 'op://vault/item/field')";
            };
            baseUrl = mkOption {
              type = types.str;
              default = "";
              description = "Base URL for the API (for custom endpoints)";
            };
          };
        });
        default = {};
        description = ''
          Custom models configuration for ~/.pi/agent/models.json.
          Allows adding custom providers and models.
        '';
      };

      prompts = mkOption {
        type = types.attrsOf types.lines;
        default = {};
        description = ''
          Prompt templates as attribute set.
          Each key is the prompt name, value is the template content.
          Written to ~/.pi/agent/prompts/<name>.md
        '';
      };

      skills = mkOption {
        type = types.attrsOf types.lines;
        default = {};
        description = ''
          Skills as attribute set.
          Each key is the skill name, value is the SKILL.md content.
          Written to ~/.pi/agent/skills/<name>/SKILL.md
        '';
      };

      extensions = mkOption {
        type = types.attrsOf types.lines;
        default = {};
        description = ''
          Extensions as attribute set.
          Each key is the extension name, value is the TypeScript source.
          Written to ~/.pi/agent/extensions/<name>.ts
        '';
      };

      themes = mkOption {
        type = types.attrsOf types.attrs;
        default = {};
        description = ''
          Custom themes as attribute set.
          Each key is the theme name, value is a theme attribute set.
          Written to ~/.pi/agent/themes/<name>.json
        '';
      };
    };

    microvm = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Whether this system is running inside a microvm";
      };

      ipAddress = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Static IP address for the microvm on the bridge network";
      };

      gateway = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Gateway IP for the microvm (bridge IP)";
      };
    };

    sketchybar = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Enable sketchybar status bar (macOS only)";
      };

      height = mkOption {
        type = types.int;
        default = 40;
        description = "Height of the sketchybar in pixels";
      };

      padding = mkOption {
        type = types.int;
        default = 2;
        description = "Padding on left and right of the bar";
      };

      groupPadding = mkOption {
        type = types.int;
        default = 10;
        description = "Padding between item groups";
      };

      font = {
        text = mkOption {
          type = types.str;
          default = "SF Pro";
          description = "Font family for text items";
        };

        numbers = mkOption {
          type = types.str;
          default = "SF Mono";
          description = "Font family for numbers";
        };
      };

      colors = {
        black = mkOption {
          type = types.str;
          default = "#181819";
          description = "Black color";
        };

        white = mkOption {
          type = types.str;
          default = "#e2e2e3";
          description = "White color";
        };

        red = mkOption {
          type = types.str;
          default = "#fc5d7c";
          description = "Red color";
        };

        green = mkOption {
          type = types.str;
          default = "#9ed072";
          description = "Green color";
        };

        blue = mkOption {
          type = types.str;
          default = "#76cce0";
          description = "Blue color";
        };

        yellow = mkOption {
          type = types.str;
          default = "#e7c664";
          description = "Yellow color";
        };

        orange = mkOption {
          type = types.str;
          default = "#f39660";
          description = "Orange color";
        };

        magenta = mkOption {
          type = types.str;
          default = "#b39df3";
          description = "Magenta color";
        };

        grey = mkOption {
          type = types.str;
          default = "#7f8490";
          description = "Grey color";
        };

        bar = {
          bg = mkOption {
            type = types.str;
            default = "#2c2e34";
            description = "Bar background color";
          };

          border = mkOption {
            type = types.str;
            default = "#2c2e34";
            description = "Bar border color";
          };
        };

        popup = {
          bg = mkOption {
            type = types.str;
            default = "#2c2e34";
            description = "Popup background color";
          };

          border = mkOption {
            type = types.str;
            default = "#7f8490";
            description = "Popup border color";
          };
        };

        bg1 = mkOption {
          type = types.str;
          default = "#363944";
          description = "Background level 1 color";
        };

        bg2 = mkOption {
          type = types.str;
          default = "#414550";
          description = "Background level 2 color";
        };
      };

      useAerospaceIntegration = mkOption {
        type = types.bool;
        default = true;
        description = "Enable aerospace window manager integration for workspace display";
      };

      extraConfig = mkOption {
        type = types.lines;
        default = "";
        description = "Extra Lua configuration to append to sketchybarrc";
      };
    };
  };
}
