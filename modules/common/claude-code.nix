# myConfig.claude-code options — owned here, consumed by
# modules/home-manager/claude-code.nix (loaded conditionally via
# modules/common/users.nix) and set by modules/roles/claude.nix.
{lib, ...}: {
  options.myConfig.claude-code = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable Claude Code configuration management";
    };

    includeCoAuthoredBy = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Whether to include Co-Authored-By trailers in commits";
    };

    extraSettings = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = {};
      description = "Additional Claude Code settings";
    };

    mcpServers = lib.mkOption {
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
          apiKey = lib.mkOption {
            type = lib.types.str;
            default = "";
            description = "API key for the MCP server (use onePasswordItem instead for secrets)";
          };
          onePasswordItem = lib.mkOption {
            type = lib.types.str;
            default = "";
            description = "1Password item reference (e.g., 'op://vault/item/field') to retrieve API key";
          };
        };
      });
      default = {};
      description = "MCP servers configuration for Claude Code";
    };

    agents = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = {};
      description = "Custom agents for Claude Code";
    };

    commands = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = {};
      description = "Custom commands for Claude Code";
    };

    hooks = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = {};
      description = "Custom hooks for Claude Code";
    };
  };
}
