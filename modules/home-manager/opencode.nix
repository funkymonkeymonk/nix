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

  # Transform MCP server config from our options format to opencode's expected format
  transformMcpServer = name: server:
    {
      inherit (server) enabled;
    }
    // (
      if server.type == "remote"
      then {
        type = "remote";
        inherit (server) url;
      }
      else {
        type = "local";
        inherit (server) command;
      }
    );

  # Generate markdown command files
  commandFiles = lib.mapAttrs' (name: cmd:
    lib.nameValuePair ".config/opencode/commands/${name}.md" {
      text = let
        frontmatter = lib.concatStringsSep "\n" (
          ["---"]
          ++ optional (cmd.description != "") "description: ${cmd.description}"
          ++ optional (cmd.agent != null) "agent: ${cmd.agent}"
          ++ optional (cmd.subtask != null) "subtask: ${lib.boolToString cmd.subtask}"
          ++ optional (cmd.model != null) "model: ${cmd.model}"
          ++ ["---"]
        );
      in ''
        ${frontmatter}

        ${cmd.template}
      '';
    })
  cfg.commands;

  # Build complete settings
  settings =
    {
      inherit (cfg) theme autoupdate;
      mcp =
        {
          devenv = {
            type = "local";
            command = ["devenv" "mcp"];
            enabled = true;
          };
        }
        // lib.mapAttrs transformMcpServer cfg.extraMcpServers;
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
    // (optionalAttrs (cfg.model != null) {
      inherit (cfg) model;
    })
    // (optionalAttrs (cfg.disabledProviders != []) {
      disabled_providers = cfg.disabledProviders;
    })
    // (optionalAttrs (cfg.providers != {}) {
      provider = providerConfig;
    });
in {
  config = mkIf cfg.enable {
    # RTK instructions file for OpenCode + command files
    home.file =
      {
        ".config/opencode/RTK.md" = {
          text = ''
            # RTK Token Optimization

            Use RTK-prefixed commands for token-efficient output:

            | Standard Command | RTK Equivalent | Token Savings |
            |------------------|---------------|---------------|
            | `git status` | `rtk git status` | ~80% |
            | `git diff` | `rtk git diff` | ~75% |
            | `git log` | `rtk git log` | ~80% |
            | `git push` | `rtk git push` | ~92% |
            | `ls` | `rtk ls` | ~80% |
            | `cat <file>` | `rtk read <file>` | ~70% |
            | `grep` | `rtk grep` | ~80% |
            | `cargo test` | `rtk cargo test` | ~90% |
            | `npm test` | `rtk npm test` | ~90% |
            | `ruff check` | `rtk ruff check` | ~80% |
            | `pytest` | `rtk pytest` | ~90% |
            | `docker ps` | `rtk docker ps` | ~80% |

            Check savings: \`rtk gain\` or \`rtk gain --graph\`
          '';
        };
      }
      // commandFiles;

    # Use home-manager's native programs.opencode
    programs.opencode = {
      enable = true;
      settings =
        settings
        // {
          instructions = ["RTK.md"];
        };
    };

    # Configure opnix secrets for providers with 1Password items
    programs.onepassword-secrets = mkIf (providersWithSecrets != {} && osConfig.myConfig.onepassword.enable) {
      enable = true;
      secrets = opnixSecrets;
    };
  };
}
