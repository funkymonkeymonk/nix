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
          description = "Developer workstation/desktop tools (slack, trippy, unar)";
        };
      };
      work = {
        enable = mkOption {
          type = types.bool;
          default = false;
          description = "This machine is used for an employer/work context (as opposed to purely personal use). Orthogonal to workstation (machine form-factor) — set explicitly per-host, not via a shared archetype.";
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
      homebrew = {
        enable = mkOption {
          type = types.bool;
          default = false;
          description = "Homebrew integration for macOS (requires Homebrew to be installed)";
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

      agentsMd = mkOption {
        type = types.lines;
        default = "";
        description = ''
          Global AGENTS.md content installed to ~/.config/opencode/AGENTS.md.
          Loaded at startup by OpenCode as global agent instructions.
          Mirrors the pi agentsMd pattern.
        '';
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
            reasoning = mkOption {
              type = types.bool;
              default = false;
              description = "Whether the model supports extended thinking/reasoning";
            };
            maxTokens = mkOption {
              type = types.nullOr types.int;
              default = null;
              description = "Maximum output tokens for the model";
            };
            compat = mkOption {
              type = types.attrsOf (types.oneOf [types.bool types.str]);
              default = {};
              description = ''
                Compatibility settings for the model provider.
                Common keys: supportsDeveloperRole, supportsReasoningEffort,
                supportsUsageInStreaming, maxTokensField, thinkingFormat.
                Set supportsDeveloperRole = false for local OpenAI-compatible
                servers that do not understand the "developer" role.
              '';
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

      pluginsSource = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = ''
          Path to the pi-plugins repository.
          Set to inputs.pi-plugins for the locked flake version,
          or an absolute local path (e.g., /home/user/src/pi-plugins) for development.
          When null, no plugins are copied from an external source.
        '';
      };

      plugins = mkOption {
        type = types.listOf types.str;
        default = [];
        description = ''
          List of plugin names to install from pluginsSource.
          Each name corresponds to a package in packages/<name>/src/index.ts
          within the pi-plugins repository.
          The plugin's extension is copied to ~/.pi/agent/extensions/<name>.ts
          and any matching skill in .pi/skills/<name>/ is copied to ~/.pi/agent/skills/.
        '';
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
