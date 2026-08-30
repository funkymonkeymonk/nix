# Home-manager module option tests using evalModules
# Tests opencode options, aerospace options, and shell alias structure
{pkgs, ...}: let
  inherit (pkgs) lib;
  stubs = import ./stubs.nix {inherit pkgs;};

  # base stubs: options.nix + hostPlatform + environment + programs + homebrew + pkgs args
  stubModules = stubs.base;

  # aerospace.nix declares myConfig.aerospace and sets services.aerospace +
  # environment.systemPackages — needs services stub on top of base.
  aerospaceStubs = stubs.aerospace;

  # --- aerospace option tests ---

  # Evaluate aerospace with defaults (externalMonitor = null)
  aerospaceDefaults =
    (lib.evalModules {
      modules = aerospaceStubs;
    }).config.myConfig.aerospace;

  # Evaluate aerospace with externalMonitor set
  aerospaceCustom =
    (lib.evalModules {
      modules =
        aerospaceStubs
        ++ [
          {
            config.myConfig.aerospace = {
              externalMonitor = "TEST";
            };
          }
        ];
    }).config.myConfig.aerospace;

  # --- opencode option tests ---

  # Evaluate opencode with defaults
  opencodeDefaults =
    (lib.evalModules {
      modules = stubModules;
    }).config.myConfig.opencode;

  # Evaluate opencode with custom values
  opencodeCustom =
    (lib.evalModules {
      modules =
        stubModules
        ++ [
          {
            config.myConfig.opencode = {
              enable = true;
              model = "claude-3-5-sonnet";
              theme = "dark";
              providers = {
                custom-provider = {
                  name = "My Provider";
                  baseURL = "https://api.example.com/v1";
                };
              };
              extraMcpServers = {
                test-server = {
                  type = "local";
                  command = ["node" "server.js"];
                };
              };
            };
          }
        ];
    }).config.myConfig.opencode;

  # Evaluate the OpenCode role defaults, including its generated Bifrost
  # provider and default model.
  opencodeRole =
    (lib.evalModules {
      modules =
        stubs.withRoles
        ++ [
          {
            config.myConfig = {
              roles.opencode.enable = true;
            };
          }
        ];
    }).config.myConfig;

  opencodeHome =
    (lib.evalModules {
      modules = [
        {
          options.home = {
            file = lib.mkOption {
              type = lib.types.attrsOf lib.types.anything;
              default = {};
            };
            sessionVariables = lib.mkOption {
              type = lib.types.attrsOf lib.types.str;
              default = {};
            };
          };
          options.programs = lib.mkOption {
            type = lib.types.attrsOf lib.types.anything;
            default = {};
          };
        }
        {
          config._module.args = {
            inherit pkgs;
            osConfig = {myConfig = opencodeRole;};
          };
        }
        ../modules/home-manager/opencode.nix
      ];
    }).config;

  # --- shell aliases test ---
  # Import aliases.nix as a home-manager module to check it defines shellAliases
  # Note: aliases.nix reads from config.myConfig which needs the options module
  aliasesEval = lib.evalModules {
    modules =
      stubModules
      ++ [
        {
          # Stub home-manager options that aliases.nix sets
          options.home.shellAliases = lib.mkOption {
            type = lib.types.attrsOf lib.types.str;
            default = {};
          };
          # aliases.nix accesses config.myConfig.onepassword.enable via `or {}`
          # guard — no explicit onepassword stub needed here.
        }
        ../modules/home-manager/aliases.nix
      ];
  };
  inherit (aliasesEval.config.home) shellAliases;
in {
  # Test opencode option defaults
  opencodeOptionsTest =
    pkgs.runCommand "test-opencode-options"
    {}
    ''
      echo "=== Testing OpenCode Option Defaults ==="

      ${
        if !opencodeDefaults.enable
        then ''echo "  enable default = false: OK"''
        else ''echo "  enable should default to false!"; exit 1''
      }

      ${
        if opencodeDefaults.providers == {}
        then ''echo "  providers default = {}: OK"''
        else ''echo "  providers should default to empty!"; exit 1''
      }

      ${
        if opencodeDefaults.extraMcpServers == {}
        then ''echo "  extraMcpServers default = {}: OK"''
        else ''echo "  extraMcpServers should default to empty!"; exit 1''
      }

      ${
        if opencodeDefaults.model == null
        then ''echo "  model default = null: OK"''
        else ''echo "  model should default to null!"; exit 1''
      }

      ${
        if opencodeDefaults.theme == "system"
        then ''echo "  theme default = system: OK"''
        else ''echo "  theme should default to system!"; exit 1''
      }

      echo "All opencode option defaults verified"
      touch $out
    '';

  # Test opencode custom option values
  opencodeCustomOptionsTest =
    pkgs.runCommand "test-opencode-custom-options"
    {}
    ''
      echo "=== Testing OpenCode Custom Options ==="

      ${
        if opencodeCustom.enable
        then ''echo "  enable = true: OK"''
        else ''echo "  enable should be true!"; exit 1''
      }

      ${
        if opencodeCustom.providers ? custom-provider
        then ''echo "  providers.custom-provider defined: OK"''
        else ''echo "  providers.custom-provider should be defined!"; exit 1''
      }

      ${
        if opencodeCustom.extraMcpServers ? test-server
        then ''echo "  extraMcpServers.test-server defined: OK"''
        else ''echo "  extraMcpServers.test-server should be defined!"; exit 1''
      }

      ${
        if opencodeCustom.model == "claude-3-5-sonnet"
        then ''echo "  model = claude-3-5-sonnet: OK"''
        else ''echo "  model should be claude-3-5-sonnet!"; exit 1''
      }

      ${
        if opencodeCustom.theme == "dark"
        then ''echo "  theme = dark: OK"''
        else ''echo "  theme should be dark!"; exit 1''
      }

      echo "All opencode custom options verified"
      touch $out
    '';

  # Test the role's Bifrost provider uses the Anthropic-compatible API and
  # enables the discovery plugin without removing other providers.
  opencodeBifrostDefaultsTest =
    pkgs.runCommand "test-opencode-bifrost-defaults"
    {}
    ''
      echo "=== Testing OpenCode Bifrost Defaults ==="

      ${
        if opencodeRole.opencode.enable
        then ''echo "  OpenCode role enables OpenCode configuration: OK"''
        else ''echo "  OpenCode role should enable OpenCode configuration!"; exit 1''
      }

      ${
        if opencodeRole.opencode.model == "local-bifrost/omlx/qwen3.8-27b"
        then ''echo "  default model = local-bifrost/omlx/qwen3.8-27b: OK"''
        else ''echo "  default model should be the managed Qwen model!"; exit 1''
      }

      ${
        if opencodeRole.opencode.providers.local-bifrost.npm == "@ai-sdk/anthropic"
        then ''echo "  Bifrost adapter = @ai-sdk/anthropic: OK"''
        else ''echo "  Bifrost adapter should be @ai-sdk/anthropic!"; exit 1''
      }

      ${
        if opencodeRole.opencode.providers.local-bifrost.apiKey == "bifrost-local"
        then ''echo "  Bifrost local API key configured: OK"''
        else ''echo "  Bifrost local API key should be configured!"; exit 1''
      }

      ${
        if opencodeRole.opencode.providers.local-bifrost.models ? "omlx/qwen3.8-27b"
        then ''echo "  oMLX model explicitly configured: OK"''
        else ''echo "  oMLX model should be explicitly configured!"; exit 1''
      }

      ${
        if opencodeRole.opencode.providers ? local-bifrost
        then ''echo "  Bifrost provider preserved: OK"''
        else ''echo "  Bifrost provider should be configured!"; exit 1''
      }

      ${
        if opencodeHome.programs.opencode.settings.model == "local-bifrost/omlx/qwen3.8-27b"
        then ''echo "  generated OpenCode default model = managed Qwen: OK"''
        else ''echo "  generated OpenCode default model is incorrect!"; exit 1''
      }

      ${
        if opencodeHome.programs.opencode.settings.provider.local-bifrost.npm == "@ai-sdk/anthropic"
        then ''echo "  generated Anthropic adapter = @ai-sdk/anthropic: OK"''
        else ''echo "  generated Anthropic adapter is incorrect!"; exit 1''
      }

      ${
        if opencodeHome.programs.opencode.settings.provider.local-bifrost.options.apiKey == "bifrost-local"
        then ''echo "  generated Bifrost local API key: OK"''
        else ''echo "  generated Bifrost local API key is incorrect!"; exit 1''
      }

      ${
        if opencodeHome.programs.opencode.settings.provider.local-bifrost.options.baseURL == "http://127.0.0.1:8081/anthropic/v1"
        then ''echo "  generated Bifrost API URL = port 8081: OK"''
        else ''echo "  generated Bifrost API URL should use port 8081!"; exit 1''
      }

      ${
        if opencodeHome.programs.opencode.settings.provider.local-bifrost.options.modelsDiscovery.endpoint == "/v1/models"
        then ''echo "  generated Bifrost discovery URL = /v1/models: OK"''
        else ''echo "  generated Bifrost discovery URL should be /v1/models!"; exit 1''
      }

      ${
        if opencodeHome.programs.opencode.settings.provider.local-bifrost.options.modelsDiscovery.modelInfoFormat == "bifrost"
        then ''echo "  generated Bifrost metadata discovery: OK"''
        else ''echo "  generated Bifrost metadata discovery is incorrect!"; exit 1''
      }

      ${
        if builtins.elem "opencode-models-discovery@latest" opencodeHome.programs.opencode.settings.plugin
        then ''echo "  discovery plugin loaded: OK"''
        else ''echo "  discovery plugin should be loaded!"; exit 1''
      }

      echo "All OpenCode Bifrost defaults verified"
      touch $out
    '';

  # Test shell aliases are defined
  shellAliasesTest =
    pkgs.runCommand "test-shell-aliases"
    {}
    ''
      echo "=== Testing Shell Aliases ==="

      # Verify jj aliases exist
      ${
        if shellAliases ? jjn
        then ''echo "  jjn (jj new) alias defined: OK"''
        else ''echo "  jjn alias should be defined!"; exit 1''
      }

      ${
        if shellAliases ? jjl
        then ''echo "  jjl (jj log) alias defined: OK"''
        else ''echo "  jjl alias should be defined!"; exit 1''
      }

      ${
        if shellAliases ? jjd
        then ''echo "  jjd (jj diff) alias defined: OK"''
        else ''echo "  jjd alias should be defined!"; exit 1''
      }

      # Verify opencode alias
      ${
        if shellAliases ? oc
        then ''echo "  oc (opencode) alias defined: OK"''
        else ''echo "  oc alias should be defined!"; exit 1''
      }

      # Verify devenv task aliases
      ${
        if shellAliases ? dtr
        then ''echo "  dtr (devenv tasks run) alias defined: OK"''
        else ''echo "  dtr alias should be defined!"; exit 1''
      }

      ${
        if shellAliases ? dtl
        then ''echo "  dtl (devenv tasks list) alias defined: OK"''
        else ''echo "  dtl alias should be defined!"; exit 1''
      }

      # Verify ops alias (conditional on 1Password)
      ${
        if shellAliases ? ops
        then ''echo "  ops alias defined: OK"''
        else ''echo "  ops alias should be defined!"; exit 1''
      }

      echo "  Total aliases: ${toString (builtins.length (builtins.attrNames shellAliases))}"
      echo "  Aliases: ${builtins.concatStringsSep ", " (builtins.attrNames shellAliases)}"

      echo "All shell aliases verified"
      touch $out
    '';

  # Test aerospace option defaults
  aerospaceOptionsTest =
    pkgs.runCommand "test-aerospace-options"
    {}
    ''
      echo "=== Testing aerospace Option Defaults ==="

      ${
        if aerospaceDefaults.externalMonitor == null
        then ''echo "  externalMonitor default = null: OK"''
        else ''echo "  externalMonitor should default to null!"; exit 1''
      }

      echo "All aerospace option defaults verified"
      touch $out
    '';

  # Test aerospace custom option values
  aerospaceCustomOptionsTest =
    pkgs.runCommand "test-aerospace-custom-options"
    {}
    ''
      echo "=== Testing aerospace Custom Options ==="

      ${
        if aerospaceCustom.externalMonitor == "TEST"
        then ''echo "  externalMonitor = TEST: OK"''
        else ''echo "  externalMonitor should be TEST!"; exit 1''
      }

      echo "All aerospace custom options verified"
      touch $out
    '';

  # Test opencode provider baseURLOpnixItem option default and custom value
  opencodeProviderOpnixUrlTest = let
    providerOpnixDefaultEval =
      (lib.evalModules {
        modules =
          stubModules
          ++ [
            {
              config.myConfig.opencode = {
                enable = true;
                providers = {
                  test-provider = {
                    name = "Test Provider";
                    baseURL = "https://api.example.com/v1";
                  };
                };
              };
            }
          ];
      }).config.myConfig.opencode.providers;

    providerOpnixCustomEval =
      (lib.evalModules {
        modules =
          stubModules
          ++ [
            {
              config.myConfig.opencode = {
                enable = true;
                providers = {
                  secret-provider = {
                    name = "Secret Provider";
                    baseURLOpnixItem = "op://Vault/LiteLLM/baseURL";
                  };
                };
              };
            }
          ];
      }).config.myConfig.opencode.providers;
  in
    pkgs.runCommand "test-opencode-provider-opnix-url"
    {}
    ''
      echo "=== Testing OpenCode Provider baseURLOpnixItem Options ==="

      ${
        if providerOpnixDefaultEval.test-provider.baseURLOpnixItem == ""
        then ''echo "  baseURLOpnixItem default = empty string: OK"''
        else ''echo "  baseURLOpnixItem should default to empty string!"; exit 1''
      }

      ${
        if providerOpnixDefaultEval.test-provider.baseURL == "https://api.example.com/v1"
        then ''echo "  baseURL can still be set directly: OK"''
        else ''echo "  baseURL should be settable directly!"; exit 1''
      }

      ${
        if providerOpnixCustomEval.secret-provider.baseURLOpnixItem == "op://Vault/LiteLLM/baseURL"
        then ''echo "  baseURLOpnixItem custom value: OK"''
        else ''echo "  baseURLOpnixItem should be op://Vault/LiteLLM/baseURL!"; exit 1''
      }

      ${
        if providerOpnixCustomEval.secret-provider.baseURL == ""
        then ''echo "  baseURL defaults to empty when using opnix: OK"''
        else ''echo "  baseURL should default to empty string!"; exit 1''
      }

      echo "All opencode provider opnix URL option tests verified"
      touch $out
    '';
}
