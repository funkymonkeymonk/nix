{
  osConfig,
  lib,
  ...
}:
with lib; let
  cfg = osConfig.myConfig.opencode;
  rtkCfg = osConfig.myConfig.llmClient.rtk;
  skillsCfg = osConfig.myConfig.skills or {};
  hmLib = import ./lib.nix {inherit lib;};

  # Resolved manifest subset (internal + superpowers skills) used to build
  # bundled commands below. Skill DIRECTORY installation itself now lives in
  # modules/home-manager/skills/canonical-install.nix, under the shared
  # ~/.agents/skills/<name> location — not duplicated here.
  inherit
    (hmLib.mkFullSkillDirs {
      enabledRoles = skillsCfg.enabledRoles or [];
      superpowersPath = skillsCfg.superpowersPath or null;
    })
    allSkills
    ;

  # Commands bundled with skills (e.g. jj's /finish /pr /push, yak-shaving's /shave)
  skillCommands = hmLib.mkSkillCommands allSkills;

  # Auto-loaded digest content (subset of skillDirs tagged autoLoad = true,
  # concatenated into one file). This is a separate opencode feature from
  # skill directories: opencode.json's `instructions` list points at files
  # to load unconditionally into every session's context.
  inherit
    (hmLib.mkAutoLoadSkills {
      enabledRoles = skillsCfg.enabledRoles or [];
      superpowersPath = skillsCfg.superpowersPath or null;
    })
    autoLoadContent
    hasAutoLoadSkills
    ;

  # Filter providers that have 1Password items configured
  providersWithSecrets = lib.filterAttrs (_name: provider: provider.onePasswordItem != "") cfg.providers;

  # Filter providers that have baseURLOpnixItem configured
  providersWithBaseURLSecrets = lib.filterAttrs (_name: provider: provider.baseURLOpnixItem != "") cfg.providers;

  # Build opnix secrets configuration using shared helper (API keys)
  opnixSecrets = hmLib.mkOpnixSecrets "opencode" osConfig.myConfig.onepassword.defaultVault (
    lib.mapAttrs (name: provider: {
      inherit (provider) onePasswordItem;
      secretPath = ".config/opencode/secrets/${name}-apikey";
    })
    providersWithSecrets
  );

  # Build opnix secrets for base URLs (providers with baseURLOpnixItem)
  opnixBaseURLSecrets = hmLib.mkOpnixSecretsGeneric "opencode" osConfig.myConfig.onepassword.defaultVault (
    lib.mapAttrs (name: provider: {
      reference = provider.baseURLOpnixItem;
      path = ".config/opencode/secrets/${name}-baseurl";
    })
    providersWithBaseURLSecrets
  );

  # Combined opnix secrets (API keys + base URLs)
  allOpnixSecrets = opnixSecrets // opnixBaseURLSecrets;

  # Providers that want their model list fetched at runtime (e.g. LiteLLM
  # proxies). Model discovery itself is handled by the opencode-models-discovery
  # plugin (https://www.npmjs.com/package/opencode-models-discovery), not by
  # any custom script — we just need to opt each provider in via
  # options.modelsDiscovery and make sure the plugin is loaded.
  providersWithDynamicModels = lib.filterAttrs (_name: provider: provider.dynamicModels or false) cfg.providers;
  hasDynamicModels = providersWithDynamicModels != {};

  # Build provider config with API key references (only if onePasswordItem is set)
  providerConfig =
    lib.mapAttrs (
      _name: provider: let
        hasSecretApiKey = (provider.onePasswordItem or "") != "";
        hasApiKey = hasSecretApiKey || provider.apiKey != null;
        hasModels = provider.models or {} != {};
        baseOptions = {inherit (provider) baseURL;};
        optionsWithKey =
          baseOptions
          // {
            apiKey =
              if hasSecretApiKey
              then "{file:~/.config/opencode/secrets/${_name}-apikey}"
              else provider.apiKey;
          };
        optionsWithDiscovery =
          if provider.dynamicModels or false
          then {
            modelsDiscovery = {
              enabled = true;
              endpoint = "/v1/models";
              smartModelName = true;
              modelInfoFormat = "bifrost";
              cache.enabled = true;
            };
          }
          else {};
        baseConfig =
          {
            inherit (provider) name;
            options =
              (
                if hasApiKey
                then optionsWithKey
                else baseOptions
              )
              // optionsWithDiscovery;
          }
          // (optionalAttrs hasModels {inherit (provider) models;});
      in
        baseConfig // (optionalAttrs (provider.npm != null) {inherit (provider) npm;})
    )
    cfg.providers;

  # Transform MCP server config from our options format to opencode's expected format
  transformMcpServer = _name: server:
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

  # Generate command content (name -> markdown string), consumed by
  # programs.opencode.commands below.
  commandFiles =
    lib.mapAttrs (_name: cmd: let
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
    '')
    cfg.commands;

  # Build agent config
  agentConfig = lib.mapAttrs (_name: agent:
    {
      inherit (agent) description mode;
    }
    // (optionalAttrs (agent.model != null) {
      inherit (agent) model;
    })
    // (optionalAttrs (agent.prompt != "") {
      inherit (agent) prompt;
    })
    // (optionalAttrs (agent.temperature != null) {
      inherit (agent) temperature;
    })
    // (optionalAttrs agent.hidden {
      inherit (agent) hidden;
    })
    // (optionalAttrs (agent.tools != {}) {
      inherit (agent) tools;
    })
    // (optionalAttrs (agent.permission != {}) {
      inherit (agent) permission;
    })
    // (optionalAttrs (agent.color != "") {
      inherit (agent) color;
    }))
  cfg.agents;

  # Build complete settings (TUI-specific keys like theme go in tui.json, not here)
  settings =
    {
      inherit (cfg) autoupdate;
      mcp =
        {
          # Disabled by default so it doesn't consume context until needed —
          # enable per-session with the /mcp command or by overriding
          # extraMcpServers.devenv.enabled = true.
          devenv = {
            type = "local";
            command = ["devenv" "mcp"];
            enabled = false;
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
    })
    // (optionalAttrs (cfg.agents != {}) {
      agent = agentConfig;
    })
    // (optionalAttrs hasDynamicModels {
      plugin = ["opencode-models-discovery@latest"];
    });
in {
  config = mkIf cfg.enable {
    # Point opencode at a machine-local private config that is NOT managed by
    # Nix. opencode natively merges this with the Nix-managed
    # ~/.config/opencode/opencode.json (global config) per its documented
    # config precedence (https://opencode.ai/docs/config/#custom-path) —
    # OPENCODE_CONFIG sits between global and project config, with its keys
    # overriding global config on conflicts. Create this file by hand to add
    # personal providers, MCP servers, or secrets that shouldn't live in Nix.
    home.sessionVariables = {
      OPENCODE_CONFIG = "$HOME/.config/opencode/opencode-private.json";
    };

    # RTK instructions file for OpenCode (only when RTK is enabled) + auto-loaded skills digest
    home.file =
      {
        # TUI configuration - must be kept in sync with main config theme
        ".config/opencode/tui.json" = {
          force = true;
          text = builtins.toJSON {
            "$schema" = "https://opencode.ai/tui.json";
            inherit (cfg) theme;
          };
        };
      }
      // (optionalAttrs (cfg.agentsMd != "") {
        ".config/opencode/AGENTS.md" = {
          text = cfg.agentsMd;
        };
      })
      // (optionalAttrs rtkCfg.enable {
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
      })
      // (optionalAttrs hasAutoLoadSkills {
        # Digest of autoLoad = true skills, referenced via opencode.json's
        # `instructions` list below. This is separate from the full skill
        # directories installed via programs.opencode.skills — opencode
        # reads `instructions` unconditionally into every session's
        # context, whereas skill directories are discovered on demand.
        ".config/opencode/skills/auto-loaded.md" = {
          text = autoLoadContent;
        };
      });

    programs = {
      # Use home-manager's native programs.opencode
      opencode = {
        enable = true;
        commands = commandFiles // skillCommands;
        settings = let
          # Build instructions list: RTK docs + any auto-loaded skills
          instructionFiles =
            lib.optional rtkCfg.enable "RTK.md"
            ++ lib.optional hasAutoLoadSkills "skills/auto-loaded.md";
        in
          settings
          // {instructions = instructionFiles;};
      };

      # Configure opnix secrets for providers with 1Password items (API keys + base URLs)
      onepassword-secrets = mkIf ((allOpnixSecrets != {}) && osConfig.myConfig.onepassword.enable) {
        enable = true;
        secrets = allOpnixSecrets;
      };
    };
  };
}
