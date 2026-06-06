# Home-manager module option tests using evalModules
# Tests jj-autosync options, opencode options, fjj options, aerospace options, and shell alias structure
{pkgs, ...}: let
  inherit (pkgs) lib;

  # Shared stub modules for options-level evaluation
  stubModules = [
    ../modules/common/options.nix
    {
      options.nixpkgs.hostPlatform = lib.mkOption {
        type = lib.types.anything;
        default = {inherit (pkgs.stdenv.hostPlatform) system;};
      };
    }
    {
      config._module.args = {inherit pkgs;};
    }
  ];

  # --- aerospace option tests ---

  # Evaluate aerospace with defaults (externalMonitor = null)
  aerospaceDefaults =
    (lib.evalModules {
      modules = stubModules;
    }).config.myConfig.aerospace;

  # Evaluate aerospace with externalMonitor set
  aerospaceCustom =
    (lib.evalModules {
      modules =
        stubModules
        ++ [
          {
            config.myConfig.aerospace = {
              externalMonitor = "TEST";
            };
          }
        ];
    }).config.myConfig.aerospace;

  # --- fjj option tests ---

  # Evaluate fjj with defaults
  fjjDefaults =
    (lib.evalModules {
      modules = stubModules;
    }).config.myConfig.fjj;

  # Evaluate fjj with a custom mirrorRoot
  fjjCustom =
    (lib.evalModules {
      modules =
        stubModules
        ++ [
          {
            config.myConfig.fjj = {
              enable = true;
              mirrorRoot = "/custom/mirror";
              workspaceRoot = "/custom/workspaces";
            };
          }
        ];
    }).config.myConfig.fjj;

  # --- jj-autosync option tests ---

  # Evaluate jj-autosync with defaults
  jjAutosyncDefaults =
    (lib.evalModules {
      modules = stubModules;
    }).config.myConfig.jj-autosync;

  # Evaluate jj-autosync with custom values
  jjAutosyncCustom =
    (lib.evalModules {
      modules =
        stubModules
        ++ [
          {
            config.myConfig.jj-autosync = {
              enable = true;
              username = "testuser";
              reposDir = "/home/testuser/code";
              mainBranch = "develop";
              hourlySync = false;
              fastSyncInterval = 120;
              sessionTtlSeconds = 3600;
            };
          }
        ];
    }).config.myConfig.jj-autosync;

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

  # --- shell aliases test ---
  # Import aliases.nix as a home-manager module to check it defines shellAliases
  # Note: aliases.nix reads from config.myConfig which needs the options module
  aliasesEval = lib.evalModules {
    modules = [
      ../modules/common/options.nix
      {
        options.nixpkgs.hostPlatform = lib.mkOption {
          type = lib.types.anything;
          default = {inherit (pkgs.stdenv.hostPlatform) system;};
        };
        # Stub home-manager options that aliases.nix sets
        options.home.shellAliases = lib.mkOption {
          type = lib.types.attrsOf lib.types.str;
          default = {};
        };
        # Stub myConfig at the level aliases.nix expects
        # (aliases.nix accesses config.myConfig.onepassword.enable)
      }
      ../modules/home-manager/aliases.nix
      {
        config._module.args = {inherit pkgs;};
      }
    ];
  };
  inherit (aliasesEval.config.home) shellAliases;
in {
  # Test jj-autosync option defaults
  jjAutosyncOptionsTest =
    pkgs.runCommand "test-jj-autosync-options"
    {}
    ''
      echo "=== Testing jj-autosync Option Defaults ==="

      ${
        if !jjAutosyncDefaults.enable
        then ''echo "  enable default = false: OK"''
        else ''echo "  enable should default to false!"; exit 1''
      }

      ${
        if jjAutosyncDefaults.username == ""
        then ''echo "  username default = empty: OK"''
        else ''echo "  username should default to empty!"; exit 1''
      }

      ${
        if jjAutosyncDefaults.mainBranch == "main"
        then ''echo "  mainBranch default = main: OK"''
        else ''echo "  mainBranch should default to main!"; exit 1''
      }

      ${
        if jjAutosyncDefaults.hourlySync
        then ''echo "  hourlySync default = true: OK"''
        else ''echo "  hourlySync should default to true!"; exit 1''
      }

      ${
        if jjAutosyncDefaults.fastSyncInterval == 300
        then ''echo "  fastSyncInterval default = 300: OK"''
        else ''echo "  fastSyncInterval should default to 300!"; exit 1''
      }

      ${
        if jjAutosyncDefaults.sessionTtlSeconds == 1800
        then ''echo "  sessionTtlSeconds default = 1800: OK"''
        else ''echo "  sessionTtlSeconds should default to 1800!"; exit 1''
      }

      echo "All jj-autosync option defaults verified"
      touch $out
    '';

  # Test jj-autosync custom option values
  jjAutosyncCustomOptionsTest =
    pkgs.runCommand "test-jj-autosync-custom-options"
    {}
    ''
      echo "=== Testing jj-autosync Custom Options ==="

      ${
        if jjAutosyncCustom.enable
        then ''echo "  enable = true: OK"''
        else ''echo "  enable should be true!"; exit 1''
      }

      ${
        if jjAutosyncCustom.username == "testuser"
        then ''echo "  username = testuser: OK"''
        else ''echo "  username should be testuser!"; exit 1''
      }

      ${
        if jjAutosyncCustom.reposDir == "/home/testuser/code"
        then ''echo "  reposDir = /home/testuser/code: OK"''
        else ''echo "  reposDir should be /home/testuser/code!"; exit 1''
      }

      ${
        if jjAutosyncCustom.mainBranch == "develop"
        then ''echo "  mainBranch = develop: OK"''
        else ''echo "  mainBranch should be develop!"; exit 1''
      }

      ${
        if !jjAutosyncCustom.hourlySync
        then ''echo "  hourlySync = false: OK"''
        else ''echo "  hourlySync should be false!"; exit 1''
      }

      ${
        if jjAutosyncCustom.fastSyncInterval == 120
        then ''echo "  fastSyncInterval = 120: OK"''
        else ''echo "  fastSyncInterval should be 120!"; exit 1''
      }

      ${
        if jjAutosyncCustom.sessionTtlSeconds == 3600
        then ''echo "  sessionTtlSeconds = 3600: OK"''
        else ''echo "  sessionTtlSeconds should be 3600!"; exit 1''
      }

      echo "All jj-autosync custom options verified"
      touch $out
    '';

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

  # Test fjj option defaults
  fjjOptionsTest =
    pkgs.runCommand "test-fjj-options"
    {}
    ''
      echo "=== Testing fjj Option Defaults ==="

      ${
        if !fjjDefaults.enable
        then ''echo "  enable default = false: OK"''
        else ''echo "  enable should default to false!"; exit 1''
      }

      ${
        # Default mirrorRoot depends on platform: ~/src on Darwin, /srv/github on Linux
        if (fjjDefaults.mirrorRoot == "~/src" || fjjDefaults.mirrorRoot == "/srv/github")
        then ''echo "  mirrorRoot default is platform-appropriate: OK"''
        else ''echo "  mirrorRoot should be ~/src or /srv/github, got: ${fjjDefaults.mirrorRoot}"; exit 1''
      }

      ${
        if fjjDefaults.workspaceRoot == "~/workspaces"
        then ''echo "  workspaceRoot default = ~/workspaces: OK"''
        else ''echo "  workspaceRoot should default to ~/workspaces!"; exit 1''
      }

      echo "All fjj option defaults verified"
      touch $out
    '';

  # Test fjj custom option values
  fjjCustomOptionsTest =
    pkgs.runCommand "test-fjj-custom-options"
    {}
    ''
      echo "=== Testing fjj Custom Options ==="

      ${
        if fjjCustom.enable
        then ''echo "  enable = true: OK"''
        else ''echo "  enable should be true!"; exit 1''
      }

      ${
        if fjjCustom.mirrorRoot == "/custom/mirror"
        then ''echo "  mirrorRoot = /custom/mirror: OK"''
        else ''echo "  mirrorRoot should be /custom/mirror!"; exit 1''
      }

      ${
        if fjjCustom.workspaceRoot == "/custom/workspaces"
        then ''echo "  workspaceRoot = /custom/workspaces: OK"''
        else ''echo "  workspaceRoot should be /custom/workspaces!"; exit 1''
      }

      echo "All fjj custom options verified"
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
