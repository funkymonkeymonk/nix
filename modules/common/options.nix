{
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
  };
}
