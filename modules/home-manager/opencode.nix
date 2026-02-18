{
  config,
  osConfig,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = osConfig.myConfig.opencode;

  # Filter providers that have 1Password items configured
  providersWithSecrets = lib.filterAttrs (name: provider: provider.onePasswordItem != "") cfg.providers;

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

  # Build opnix secrets configuration
  opnixSecrets = lib.mapAttrs' (name: provider:
    lib.nameValuePair "opencode${toCamelCase name}ApiKey" {
      reference = provider.onePasswordItem;
      path = ".config/opencode/secrets/${name}-apikey";
      mode = "0600";
    })
  providersWithSecrets;

  # Build provider config with API key references
  providerConfig =
    lib.mapAttrs (name: provider: {
      inherit (provider) npm name;
      options = {
        inherit (provider) baseURL;
        apiKey = "{file:~/.config/opencode/secrets/${name}-apikey}";
      };
      inherit (provider) models;
    })
    cfg.providers;

  # Build complete settings
  settings =
    {
      inherit (cfg) theme model autoupdate;
      mcp =
        {
          devenv = {
            type = "local";
            command = ["devenv" "mcp"];
            enabled = true;
          };
        }
        // cfg.extraMcpServers;
      permission = {
        bash = {
          "task *" = "allow";
          "npx *" = "allow";
          "npm *" = "allow";
        };
      };
      tools = {
        devenv = true;
      };
    }
    // (optionalAttrs (cfg.providers != {}) {
      provider = providerConfig;
    });
in {
  config = mkIf cfg.enable {
    # Use home-manager's native programs.opencode
    programs.opencode = {
      enable = true;
      inherit settings;
    };

    # Configure opnix secrets for providers with 1Password items
    programs.onepassword-secrets = mkIf (providersWithSecrets != {} && osConfig.myConfig.onepassword.enable) {
      enable = true;
      secrets = opnixSecrets;
    };
  };
}
