# Service module option tests using evalModules
# Tests vane and openclaw options without requiring platform-specific modules
{pkgs, ...}: let
  inherit (pkgs) lib;

  # Shared stub modules for evalModules
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

  # Evaluate vane options with defaults
  vaneDefaultEval =
    (lib.evalModules {
      modules =
        stubModules
        ++ [
          {
            config.myConfig.vane.enable = false;
          }
        ];
    }).config.myConfig.vane;

  # Evaluate vane with custom values
  vaneCustomEval =
    (lib.evalModules {
      modules =
        stubModules
        ++ [
          {
            config.myConfig.vane = {
              enable = true;
              port = 8080;
              embeddedSearxng = false;
              searxngUrl = "http://my-searxng:9090";
              embeddedOllama = true;
              defaultModel = "llama3.2";
              embeddingModel = "mxbai-embed-large";
              autoStart = true;
              colima.cpu = 8;
              colima.memory = 16;
            };
          }
        ];
    }).config.myConfig.vane;

  # Stub modules for evaluating the vane darwin module
  vaneDarwinStubs = [
    ../modules/common/options.nix
    {
      options.nixpkgs.hostPlatform = lib.mkOption {
        type = lib.types.anything;
        default = {inherit (pkgs.stdenv.hostPlatform) system;};
      };
      # Darwin-specific stubs
      options.environment = {
        systemPackages = lib.mkOption {
          type = lib.types.listOf lib.types.package;
          default = [];
        };
        shellAliases = lib.mkOption {
          type = lib.types.attrsOf lib.types.anything;
          default = {};
        };
      };
      options.launchd.user.agents = lib.mkOption {
        type = lib.types.attrsOf lib.types.anything;
        default = {};
      };
      options.system.activationScripts = lib.mkOption {
        type = lib.types.attrsOf lib.types.anything;
        default = {};
      };
    }
    {
      config._module.args = {inherit pkgs;};
    }
  ];

  # Evaluate vane darwin module with autoStart = false (default)
  vaneDarwinDefaultEval =
    (lib.evalModules {
      modules =
        vaneDarwinStubs
        ++ [
          ../modules/services/vane/darwin.nix
          {
            config.myConfig.vane = {
              enable = true;
              autoStart = false;
            };
            config.myConfig.users = [{name = "testuser";}];
            config.myConfig.isDarwin = true;
          }
        ];
    })
    .config
    .launchd
    .user
    .agents
    .vane
    .serviceConfig;

  # Evaluate vane darwin module with autoStart = true
  vaneDarwinAutoStartEval =
    (lib.evalModules {
      modules =
        vaneDarwinStubs
        ++ [
          ../modules/services/vane/darwin.nix
          {
            config.myConfig.vane = {
              enable = true;
              autoStart = true;
            };
            config.myConfig.users = [{name = "testuser";}];
            config.myConfig.isDarwin = true;
          }
        ];
    })
    .config
    .launchd
    .user
    .agents
    .vane
    .serviceConfig;

  # Evaluate openclaw options directly (it has its own option namespace)
  openclawEval =
    (lib.evalModules {
      modules = [
        ../modules/services/openclaw/legacy.nix
        {
          options.nixpkgs.hostPlatform = lib.mkOption {
            type = lib.types.anything;
            default = {inherit (pkgs.stdenv.hostPlatform) system;};
          };
          # Stub NixOS-specific options that openclaw references
          options.environment = {
            systemPackages = lib.mkOption {
              type = lib.types.listOf lib.types.package;
              default = [];
            };
            etc = lib.mkOption {
              type = lib.types.attrsOf lib.types.anything;
              default = {};
            };
          };
          options.users = lib.mkOption {
            type = lib.types.anything;
            default = {};
          };
          options.systemd = lib.mkOption {
            type = lib.types.anything;
            default = {};
          };
          options.system = lib.mkOption {
            type = lib.types.anything;
            default = {};
          };
          options.networking = lib.mkOption {
            type = lib.types.anything;
            default = {};
          };
        }
        {
          config._module.args = {inherit pkgs;};
        }
      ];
    }).config.services.openclaw;
in {
  # Test vane option defaults
  vaneOptionsTest =
    pkgs.runCommand "test-vane-options"
    {}
    ''
      echo "=== Testing Vane Option Defaults ==="

      ${
        if !vaneDefaultEval.enable
        then ''echo "  enable default = false: OK"''
        else ''echo "  enable should default to false!"; exit 1''
      }

      ${
        if vaneDefaultEval.port == 3000
        then ''echo "  port default = 3000: OK"''
        else ''echo "  port should default to 3000!"; exit 1''
      }

      ${
        if vaneDefaultEval.embeddedSearxng
        then ''echo "  embeddedSearxng default = true: OK"''
        else ''echo "  embeddedSearxng should default to true!"; exit 1''
      }

      ${
        if !vaneDefaultEval.embeddedOllama
        then ''echo "  embeddedOllama default = false: OK"''
        else ''echo "  embeddedOllama should default to false!"; exit 1''
      }

      ${
        if !vaneDefaultEval.autoStart
        then ''echo "  autoStart default = false: OK"''
        else ''echo "  autoStart should default to false!"; exit 1''
      }

      ${
        if vaneDefaultEval.colima.cpu == 4
        then ''echo "  colima.cpu default = 4: OK"''
        else ''echo "  colima.cpu should default to 4!"; exit 1''
      }

      ${
        if vaneDefaultEval.colima.memory == 8
        then ''echo "  colima.memory default = 8: OK"''
        else ''echo "  colima.memory should default to 8!"; exit 1''
      }

      echo "All vane option defaults verified"
      touch $out
    '';

  # Test vane custom option values
  vaneCustomOptionsTest =
    pkgs.runCommand "test-vane-custom-options"
    {}
    ''
      echo "=== Testing Vane Custom Options ==="

      ${
        if vaneCustomEval.enable
        then ''echo "  enable = true: OK"''
        else ''echo "  enable should be true!"; exit 1''
      }

      ${
        if vaneCustomEval.port == 8080
        then ''echo "  port = 8080: OK"''
        else ''echo "  port should be 8080!"; exit 1''
      }

      ${
        if !vaneCustomEval.embeddedSearxng
        then ''echo "  embeddedSearxng = false: OK"''
        else ''echo "  embeddedSearxng should be false!"; exit 1''
      }

      ${
        if vaneCustomEval.embeddedOllama
        then ''echo "  embeddedOllama = true: OK"''
        else ''echo "  embeddedOllama should be true!"; exit 1''
      }

      ${
        if vaneCustomEval.autoStart
        then ''echo "  autoStart = true: OK"''
        else ''echo "  autoStart should be true!"; exit 1''
      }

      ${
        if vaneCustomEval.defaultModel == "llama3.2"
        then ''echo "  defaultModel = llama3.2: OK"''
        else ''echo "  defaultModel should be llama3.2!"; exit 1''
      }

      ${
        if vaneCustomEval.colima.cpu == 8
        then ''echo "  colima.cpu = 8: OK"''
        else ''echo "  colima.cpu should be 8!"; exit 1''
      }

      ${
        if vaneCustomEval.colima.memory == 16
        then ''echo "  colima.memory = 16: OK"''
        else ''echo "  colima.memory should be 16!"; exit 1''
      }

      echo "All vane custom options verified"
      touch $out
    '';

  # Test openclaw option defaults and structure
  openclawOptionsTest =
    pkgs.runCommand "test-openclaw-options"
    {}
    ''
      echo "=== Testing OpenClaw Option Defaults ==="

      ${
        if !openclawEval.enable
        then ''echo "  enable default = false: OK"''
        else ''echo "  enable should default to false!"; exit 1''
      }

      ${
        if openclawEval.port == 18789
        then ''echo "  port default = 18789: OK"''
        else ''echo "  port should default to 18789!"; exit 1''
      }

      ${
        if openclawEval.user == "openclaw"
        then ''echo "  user default = openclaw: OK"''
        else ''echo "  user should default to openclaw!"; exit 1''
      }

      ${
        if openclawEval.group == "openclaw"
        then ''echo "  group default = openclaw: OK"''
        else ''echo "  group should default to openclaw!"; exit 1''
      }

      ${
        if openclawEval.dataDir == "/var/lib/openclaw"
        then ''echo "  dataDir default = /var/lib/openclaw: OK"''
        else ''echo "  dataDir should default to /var/lib/openclaw!"; exit 1''
      }

      ${
        if openclawEval.openFirewall
        then ''echo "  openFirewall default = true: OK"''
        else ''echo "  openFirewall should default to true!"; exit 1''
      }

      # Verify hardening defaults
      ${
        if openclawEval.hardening.noNewPrivileges
        then ''echo "  hardening.noNewPrivileges default = true: OK"''
        else ''echo "  hardening.noNewPrivileges should default to true!"; exit 1''
      }

      ${
        if openclawEval.hardening.privateTmp
        then ''echo "  hardening.privateTmp default = true: OK"''
        else ''echo "  hardening.privateTmp should default to true!"; exit 1''
      }

      ${
        if openclawEval.hardening.protectSystem == "strict"
        then ''echo "  hardening.protectSystem default = strict: OK"''
        else ''echo "  hardening.protectSystem should default to strict!"; exit 1''
      }

      echo "All openclaw option defaults verified"
      touch $out
    '';

  # Test vane darwin launchd RunAtLoad respects autoStart = false (default)
  vaneDarwinAutoStartDefaultTest =
    pkgs.runCommand "test-vane-darwin-autostart-default"
    {}
    ''
      echo "=== Testing Vane Darwin autoStart=false (default) ==="

      ${
        if !vaneDarwinDefaultEval.RunAtLoad
        then ''echo "  RunAtLoad = false when autoStart = false: OK"''
        else ''echo "  RunAtLoad should be false when autoStart = false!"; exit 1''
      }

      echo "Vane darwin autoStart default verified"
      touch $out
    '';

  # Test vane darwin launchd RunAtLoad respects autoStart = true
  vaneDarwinAutoStartTrueTest =
    pkgs.runCommand "test-vane-darwin-autostart-true"
    {}
    ''
      echo "=== Testing Vane Darwin autoStart=true ==="

      ${
        if vaneDarwinAutoStartEval.RunAtLoad
        then ''echo "  RunAtLoad = true when autoStart = true: OK"''
        else ''echo "  RunAtLoad should be true when autoStart = true!"; exit 1''
      }

      echo "Vane darwin autoStart=true verified"
      touch $out
    '';

  # Test vane openaiBaseUrlOpnixItem option default and custom value
  vaneOpnixUrlOptionsTest = let
    vaneOpnixDefaultEval =
      (lib.evalModules {
        modules =
          stubModules
          ++ [
            {
              config.myConfig.vane.enable = false;
            }
          ];
      }).config.myConfig.vane;

    vaneOpnixCustomEval =
      (lib.evalModules {
        modules =
          stubModules
          ++ [
            {
              config.myConfig.vane = {
                enable = true;
                openaiBaseUrlOpnixItem = "op://Vault/Item/field";
              };
            }
          ];
      }).config.myConfig.vane;
  in
    pkgs.runCommand "test-vane-opnix-url-options"
    {}
    ''
      echo "=== Testing Vane openaiBaseUrlOpnixItem Options ==="

      ${
        if vaneOpnixDefaultEval.openaiBaseUrlOpnixItem == null
        then ''echo "  openaiBaseUrlOpnixItem default = null: OK"''
        else ''echo "  openaiBaseUrlOpnixItem should default to null!"; exit 1''
      }

      ${
        if vaneOpnixCustomEval.openaiBaseUrlOpnixItem == "op://Vault/Item/field"
        then ''echo "  openaiBaseUrlOpnixItem custom value: OK"''
        else ''echo "  openaiBaseUrlOpnixItem should be op://Vault/Item/field!"; exit 1''
      }

      ${
        if vaneOpnixCustomEval.openaiBaseUrl == null
        then ''echo "  openaiBaseUrl can be null when opnix item is set: OK"''
        else ''echo "  openaiBaseUrl should default to null!"; exit 1''
      }

      echo "All vane opnix URL option tests verified"
      touch $out
    '';
}
