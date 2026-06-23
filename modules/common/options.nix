{
  config,
  lib,
  options,
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

      assistant = {
        enable = mkOption {
          type = types.bool;
          default = false;
          description = "Agent email tools (himalaya, gmailctl) for reading, moving, and filtering Gmail";
        };
      };
      email-backup = {
        enable = mkOption {
          type = types.bool;
          default = false;
          description = "Immutable encrypted email backups (mbsync + restic + notmuch) with searchable archive";
        };
      };
      microvm-host = {
        enable = mkOption {
          type = types.bool;
          default = false;
          description = "MicroVM host infrastructure (bridge networking, DNS/connection logging, cloud-init VM discovery)";
        };
      };
      homebrew = {
        enable = mkOption {
          type = types.bool;
          default = false;
          description = "Homebrew integration for macOS (requires Homebrew to be installed)";
        };
      };
      tailscale = {
        enable = mkOption {
          type = types.bool;
          default = false;
          description = "Tailscale VPN with auto-connect via 1Password secrets";
        };
        authKeyOpnixItem = mkOption {
          type = types.str;
          default = "Tailscale/auth-key";
          description = "1Password item reference for Tailscale auth key. If the value does not start with 'op://', it is treated as 'Item/Field' and the default vault is prepended.";
        };
        exitNode = mkOption {
          type = types.bool;
          default = false;
          description = "Advertise this machine as a Tailscale exit node";
        };
        advertiseRoutes = mkOption {
          type = types.listOf types.str;
          default = [];
          description = "Additional routes to advertise (CIDR notation, e.g. [\"10.0.0.0/24\"])";
        };
      };
    };

    email-agent = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Enable agent email tools (himalaya CLI, gmailctl filters)";
      };

      enableGmailctl = mkOption {
        type = types.bool;
        default = true;
        description = "Enable gmailctl for declarative Gmail filter management. Requires one-time OAuth2 setup via 'email-filters init'.";
      };

      gmailctlConfigDir = mkOption {
        type = types.str;
        default = ".config/gmailctl";
        description = "Path relative to home directory for gmailctl configuration (Jsonnet filter definitions)";
      };
    };

    email-backup = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Enable encrypted immutable email backups (mbsync pull-only + restic + notmuch)";
      };

      accountName = mkOption {
        type = types.str;
        default = "gmail";
        description = "Name for the email account (used in Maildir subdirectory and backup tags)";
      };

      imapHost = mkOption {
        type = types.str;
        default = "imap.gmail.com";
        description = "IMAP server hostname";
      };

      imapPort = mkOption {
        type = types.port;
        default = 993;
        description = "IMAP server port";
      };

      username = mkOption {
        type = types.str;
        default = "";
        description = "Username for launchd/systemd service environment (required on Darwin)";
      };

      backupInterval = mkOption {
        type = types.int;
        default = 3600;
        description = "Backup interval in seconds (default: 3600 = 1 hour). Minimum recommended: 900 (15 min).";
      };

      maildir = mkOption {
        type = types.str;
        default = ".mail-backup";
        description = "Maildir staging path relative to home directory (ephemeral, used for sync before restic snapshot)";
      };

      resticRepo = mkOption {
        type = types.str;
        default = ".local/share/email-backup/restic-repo";
        description = "Restic repository path relative to home directory. Can also be s3:, b2:, sftp:, or rest: URLs for remote storage.";
      };

      resticPasswordFile = mkOption {
        type = types.str;
        default = ".config/email-backup/restic-password";
        description = "Path relative to home directory containing the restic repository password";
      };

      retentionDays = mkOption {
        type = types.int;
        default = 365;
        description = "Number of days to keep daily snapshots (default: 365). Hourly snapshots kept for 7 days.";
      };

      notmuchTags = {
        new = mkOption {
          type = types.str;
          default = "new";
          description = "Tag applied to new messages by notmuch";
        };

        exclude = mkOption {
          type = types.listOf types.str;
          default = ["deleted" "spam"];
          description = "Tags to exclude from search results by default";
        };
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
              default = "";
              description = "Base URL for the provider API. Can be empty when baseURLOpnixItem is set.";
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

            baseURLOpnixItem = mkOption {
              type = types.str;
              default = "";
              description = "1Password item reference (e.g., 'op://vault/item/field') to retrieve the base URL. When set, baseURL can be left empty.";
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

      sudoPasswordRef = mkOption {
        type = types.str;
        default = "";
        description = ''
          1Password reference for the sudo password used by the system:switch task.
          If empty (default), falls back to op://Private/<hostname> Sudo Password/password.
          Override this for machines with different vault or item names,
          e.g. "op://Employee/wweaver Sudo Password/password".
        '';
      };

      defaultVault = mkOption {
        type = types.str;
        default = "Personal";
        description = "Default 1Password vault for all secrets. Prepended to any opnix secret reference that does not start with 'op://'. Set per-machine to change the vault for all unqualified references.";
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
          type = types.attrsOf types.anything;
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

    bifrost = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Enable Bifrost AI gateway for unified LLM access across all local inference servers";
      };

      port = mkOption {
        type = types.port;
        default = 8081;
        description = "Port for Bifrost HTTP gateway";
      };

      host = mkOption {
        type = types.str;
        default = "0.0.0.0";
        description = "Host to bind Bifrost to";
      };

      logLevel = mkOption {
        type = types.enum ["debug" "info" "warn" "error"];
        default = "info";
        description = "Bifrost log level";
      };

      appDir = mkOption {
        type = types.str;
        default = "$HOME/.config/bifrost";
        description = "Directory for Bifrost data (config.json, SQLite DB, request logs)";
      };

      upstreams = mkOption {
        type = types.attrsOf (types.submodule {
          options = {
            url = mkOption {
              type = types.str;
              description = "Base URL for the upstream inference server (e.g., http://localhost:8300/v1)";
            };
            type = mkOption {
              type = types.enum ["openai" "vllm"];
              default = "openai";
              description = "Provider type for the upstream. Use 'vllm' for vLLM-compatible servers (uses bifrost's native vLLM provider integration)";
            };
            apiKey = mkOption {
              type = types.str;
              default = "dummy";
              description = "API key for the upstream (dummy for local servers)";
            };
            allowPrivateNetwork = mkOption {
              type = types.bool;
              default = true;
              description = "Allow connecting to private network IPs (localhost, 192.168.x.x, 10.x.x.x)";
            };
            requestTimeout = mkOption {
              type = types.ints.unsigned;
              default = 120;
              description = "Default request timeout in seconds";
            };
            models = mkOption {
              type = types.listOf types.str;
              default = [];
              description = "Model names to expose via this upstream (empty = wildcard). For vllm provider, list the models available on the vLLM server";
            };
          };
        });
        default = {};
        description = "Upstream model servers to proxy through Bifrost. Each key becomes the provider prefix for model routing (e.g., 'vllm-mlx-local' → model 'vllm-mlx-local/glm47-flash-4bit')";
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

      searxngUrl = mkOption {
        type = types.str;
        default = "http://localhost:${toString config.myConfig.searxng.port}";
        description = "URL for SearxNG API. Defaults to localhost:searxngPort";
      };

      embeddedSearxng = mkOption {
        type = types.bool;
        default = true;
        description = "Run embedded SearxNG instance for web search. Disable if using external SearxNG";
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

      openaiBaseUrlOpnixItem = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "1Password item reference (e.g., 'op://vault/item/field') to retrieve the OpenAI base URL. When set, openaiBaseUrl can be left null.";
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

      chatModels = mkOption {
        type = types.attrsOf (types.submodule {
          options = {
            name = mkOption {
              type = types.str;
              description = "Display name for the model in Vane UI";
            };
            key = mkOption {
              type = types.str;
              description = "Model key sent to the API (use 'provider-prefix/model-name' when routing through Bifrost)";
            };
          };
        });
        default = {};
        description = "Chat models exposed by Vane. If empty, falls back to the built-in vllm-mlx model configuration. When using Bifrost, set keys with provider prefix (e.g., 'vllm-mlx-local/glm47-flash-4bit')";
      };
    };

    caddy = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Enable Caddy reverse proxy with .internal hostnames to local services";
      };

      port = mkOption {
        type = types.port;
        default = 80;
        description = "Port for Caddy HTTP listener";
      };

      dataDir = mkOption {
        type = types.str;
        default = "$HOME/.local/share/caddy";
        description = "Directory for Caddy data (certs, config)";
      };

      hosts = mkOption {
        type = types.attrsOf types.str;
        default = {};
        description = "Additional hostname->upstream mappings (e.g. { \"app.internal\" = \"localhost:9000\"; })";
      };
    };

    searxng = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Enable SearXNG privacy-respecting metasearch engine";
      };

      port = mkOption {
        type = types.port;
        default = 8080;
        description = "Port for SearXNG web interface";
      };

      secretKey = mkOption {
        type = types.str;
        default = "";
        description = "Secret key for SearXNG. Auto-generated if empty. Set a stable value to avoid session resets.";
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
      default = ["qwen3:4b" "gemma3:4b"];
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
        default = "8080";
        description = "Default LLM server port for client tools (bifrost gateway)";
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
        type = types.attrsOf types.anything;
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
        type = types.attrsOf types.anything;
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

      npmPackages = mkOption {
        type = types.attrsOf types.str;
        default = {};
        description = ''
          NPM packages to install for pi extensions.
          Each key is the package name, value is the version constraint.
          Written to ~/.pi/agent/npm/package.json and installed on activation.

          Example:
          {
            "pi-web-access" = "^0.10.7";
            "pi-opencode-provider" = "^0.7.3";
          }
        '';
      };

      themes = mkOption {
        type = types.attrsOf (types.attrsOf types.anything);
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

    aerospace = {
      externalMonitor = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "External monitor identifier for aerospace workspace assignment (e.g., 'PHL'). Set to null to disable monitor-specific workspace assignment.";
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

    vllmMlx = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Enable vllm-mlx inference server for local MLX models (OpenAI + Anthropic API with multi-model hotswap)";
      };

      server = {
        host = mkOption {
          type = types.str;
          default = "0.0.0.0";
          description = "Bind address for vllm-mlx server";
        };
        port = mkOption {
          type = types.port;
          default = 8300;
          description = "Bind port for vllm-mlx server";
        };
      };

      memoryBudgetGb = mkOption {
        type = types.ints.unsigned;
        default = 24;
        description = "Memory budget in GB for model loading. Idle models are evicted under this budget.";
      };

      contention = mkOption {
        type = types.enum ["wait" "preempt" "fail"];
        default = "preempt";
        description = "Behavior when a requested model is not loaded and memory is full: wait (queue), preempt (evict current), or fail (reject).";
      };

      models = mkOption {
        type = types.attrsOf (types.submodule {
          options = {
            path = mkOption {
              type = types.str;
              description = "Model path or HuggingFace ID (e.g., mlx-community/gemma-4-12B-it-qat-4bit)";
            };
            type = mkOption {
              type = types.enum ["lm" "multimodal" "embedding"];
              default = "lm";
              description = "Model type: lm (text), multimodal (vision), or embedding";
            };
            estimatedMemoryGb = mkOption {
              type = types.nullOr types.ints.positive;
              default = null;
              description = "Estimated memory in GB for non-local (HuggingFace) models. Required for registry-backed loading so eviction remains deterministic.";
            };
          };
        });
        default = {};
        description = "Model registry. Each key is a model alias used in API requests. vllm-mlx lazily loads models on first use.";
      };

      enableAutoToolChoice = mkOption {
        type = types.bool;
        default = true;
        description = "Enable automatic tool calling. The model decides when to use tools based on the prompt.";
      };

      toolCallParser = mkOption {
        type = types.nullOr (types.enum ["auto" "none" "mistral" "qwen" "llama" "hermes" "deepseek" "kimi" "lfm2" "granite" "nemotron" "minimax" "xlam" "functionary" "glm47" "step3p5" "gemma3" "gemma3n" "xml_function" "dsml" "deepseek_v4" "zaya_xml" "hunyuan" "generic" "qwen3" "llama3" "llama4" "nous" "deepseek_v3" "deepseek_r1" "kimi_k2" "moonshot" "liquid" "granite3" "nemotron3" "minimax_m2" "meetkai" "stepfun" "glm4" "gemma4" "hy_v3" "tencent"]);
        default = null;
        description = "Tool call parser format. Must match model's training format. 'gemma4' for Gemma 4 models.";
      };

      timeout = mkOption {
        type = types.ints.unsigned;
        default = 120;
        description = "Request timeout in seconds.";
      };

      logLevel = mkOption {
        type = types.enum ["DEBUG" "INFO" "WARNING" "ERROR"];
        default = "INFO";
        description = "Server log level.";
      };
    };

    # Service registry — each service module registers its metadata here
    serviceRegistry = mkOption {
      type = types.attrsOf (types.submodule {
        options = {
          name = mkOption {
            type = types.str;
            description = "Human-readable service name";
          };
          port = mkOption {
            type = types.port;
            description = "Port the service binds to";
          };
          launchdLabel = mkOption {
            type = types.str;
            description = "launchd service label (e.g. org.vllm-mlx.server)";
          };
          errorLog = mkOption {
            type = types.str;
            description = "Path to stderr log for port conflict detection";
          };
        };
      });
      default = {};
      description = "Registry of all managed services for port conflict detection and readiness verification";
    };
  };

  # Port conflict prevention — generic check from service registry
  config = let
    services = builtins.attrValues config.myConfig.serviceRegistry;
    uniquePorts = lib.unique (map (s: s.port) services);
    conflictPorts =
      lib.filter (
        p:
          (builtins.length (builtins.filter (s: s.port == p) services)) > 1
      )
      uniquePorts;
  in
    lib.optionalAttrs (builtins.hasAttr "assertions" options) {
      assertions = [
        {
          assertion = conflictPorts == [];
          message = ''
            Port conflicts detected between enabled services:
            ${builtins.concatStringsSep "\n" (map (
                p: "  port ${toString p}: ${builtins.concatStringsSep ", " (map (s: s.name) (builtins.filter (s: s.port == p) services))}"
              )
              conflictPorts)}

            Each service must use a unique port. Change one of the conflicting service's port options.
          '';
        }
      ];
    };
}
