{lib, ...}: let
  inherit (lib) mkOption types;
in {
  options.myProfile = {
    user = {
      name = mkOption {
        type = types.str;
        description = "Username for the primary user account";
      };
      email = mkOption {
        type = types.str;
        description = "Email address for the primary user";
      };
      fullName = mkOption {
        type = types.str;
        description = "Full name of the primary user";
      };
    };

    roles = mkOption {
      type = types.attrsOf (types.submodule {
        options = {
          enable = mkOption {
            type = types.bool;
            default = false;
            description = "Enable this role";
          };
        };
      });
      default = {};
      description = "Role toggles — each key corresponds to a role in the library";
    };

    opencode = mkOption {
      type = types.submodule {
        options = {
          model = mkOption {
            type = types.nullOr types.str;
            default = null;
            description = "Default LLM model for opencode";
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
            description = "Enable browser automation agents";
          };
          disabledProviders = mkOption {
            type = types.listOf types.str;
            default = [];
            description = "List of built-in provider names to disable";
          };
        };
      };
      default = {};
      description = "OpenCode AI assistant preferences";
    };

    providers = mkOption {
      type = types.attrsOf (types.submodule {
        options = {
          npm = mkOption {
            type = types.nullOr types.str;
            default = null;
            description = "NPM package for the provider";
          };
          name = mkOption {
            type = types.str;
            description = "Display name of the provider";
          };
          baseURL = mkOption {
            type = types.str;
            default = "";
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
            description = "Fetch available models from the provider's /v1/models endpoint at runtime";
          };
          onePasswordItem = mkOption {
            type = types.str;
            default = "";
            description = "1Password item reference to retrieve API key";
          };
          baseURLOpnixItem = mkOption {
            type = types.str;
            default = "";
            description = "1Password item reference to retrieve the base URL";
          };
        };
      });
      default = {};
      description = "LLM provider configurations";
    };

    skills = mkOption {
      type = types.submodule {
        options = {
          enabledRoles = mkOption {
            type = types.listOf types.str;
            default = [];
            description = "List of enabled roles for skills filtering";
          };
          skillsPath = mkOption {
            type = types.str;
            default = ".config/opencode/skills";
            description = "Path relative to home directory where skills are installed";
          };
        };
      };
      default = {};
      description = "Agent skills preferences";
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
      description = "Additional LLM endpoint configurations";
    };

    claudeCode = mkOption {
      type = types.submodule {
        options = {
          includeCoAuthoredBy = mkOption {
            type = types.bool;
            default = false;
            description = "Include Co-Authored-By trailers in commits";
          };
        };
      };
      default = {};
      description = "Claude Code preferences";
    };
  };
}
