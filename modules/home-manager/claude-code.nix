{
  config,
  osConfig,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = osConfig.myConfig.claude-code;

  # Filter MCP servers that have 1Password items configured for API keys
  mcpServersWithSecrets = lib.filterAttrs (name: server: server.onePasswordItem != "") cfg.mcpServers;

  # Convert kebab-case to camelCase for opnix secret names
  toCamelCase = str:
    lib.concatStrings (
      lib.imap0 (
        i: s:
          if i == 0
          then s
          else lib.toUpper (lib.substring 0 1 s) + lib.substring 1 (-1) s
      ) (lib.splitString "-" str)
    );

  # Build opnix secrets configuration for MCP server API keys
  opnixSecrets = lib.mapAttrs' (name: server:
    lib.nameValuePair "claudeCode${toCamelCase name}ApiKey" {
      reference = server.onePasswordItem;
      path = ".config/claude-code/secrets/${name}-apikey";
      mode = "0600";
    })
  mcpServersWithSecrets;

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
