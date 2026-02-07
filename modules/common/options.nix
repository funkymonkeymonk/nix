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
            default = false;
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

    litellm = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Enable litellm service for LLM model management";
      };

      port = mkOption {
        type = types.port;
        default = 4000;
        description = "Port for litellm server";
      };

      masterKey = mkOption {
        type = types.str;
        default = "sk-12345";
        description = "Master key for litellm server";
      };

      openaiApiKey = mkOption {
        type = types.str;
        default = "";
        description = "OpenAI API key";
      };

      anthropicApiKey = mkOption {
        type = types.str;
        default = "";
        description = "Anthropic API key";
      };
    };
  };
}
