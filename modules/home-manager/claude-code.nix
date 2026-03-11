{
  osConfig,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = osConfig.myConfig.claude-code;
  hmLib = import ./lib.nix {inherit lib;};

  # Filter MCP servers that have 1Password items configured for API keys
  mcpServersWithSecrets = lib.filterAttrs (_name: server: server.onePasswordItem != "") cfg.mcpServers;

  # Build opnix secrets configuration using shared helper
  opnixSecrets = hmLib.mkOpnixSecrets "claudeCode" (
    lib.mapAttrs (name: server: {
      inherit (server) onePasswordItem;
      secretPath = ".config/claude-code/secrets/${name}-apikey";
    })
    mcpServersWithSecrets
  );

  # Build MCP server config with API key references
  mcpServerConfig =
    lib.mapAttrs (name: server: {
      inherit (server) type;
      url = server.url or "";
      command = server.command or [];
      enabled = server.enabled or true;
      # Add API key from file if configured
      apiKey =
        if server.onePasswordItem != ""
        then "{file:~/.config/claude-code/secrets/${name}-apikey}"
        else server.apiKey or "";
    })
    cfg.mcpServers;

  # Build complete settings
  settings =
    {
      # Default settings
      inherit (cfg) includeCoAuthoredBy;
    }
    // cfg.extraSettings
    // (optionalAttrs (cfg.mcpServers != {}) {
      mcpServers = mcpServerConfig;
    });
in {
  config = mkIf cfg.enable {
    # RTK hook script - fetched from upstream when RTK is enabled
    home.file.".claude/hooks/rtk-rewrite.sh" = mkIf cfg.rtk.enable {
      source = pkgs.fetchurl {
        url = "https://raw.githubusercontent.com/rtk-ai/rtk/master/hooks/rtk-rewrite.sh";
        sha256 = "0zw6x6zfc9rbmdd151zhhpgil1b7mxf6bzrw07mxmvcb1zmgfybr";
      };
      executable = true;
    };

    # Claude Code settings.json - managed manually to support hooks
    home.file.".claude/settings.json" = mkIf cfg.rtk.enable {
      text = let
        fullSettings =
          settings
          // {
            hooks = {
              PreToolUse = [
                {
                  matcher = "Bash";
                  hooks = [
                    {
                      type = "command";
                      command = "~/.claude/hooks/rtk-rewrite.sh";
                    }
                  ];
                }
              ];
            };
          };
      in
        builtins.toJSON fullSettings;
    };

    # Use home-manager's native programs.claude-code
    programs.claude-code = {
      enable = true;
      inherit settings;
      inherit (cfg) agents commands hooks;
    };

    # Configure opnix secrets for MCP servers with 1Password items
    programs.onepassword-secrets = mkIf (mcpServersWithSecrets != {} && osConfig.myConfig.onepassword.enable) {
      enable = true;
      secrets = opnixSecrets;
    };
  };
}
