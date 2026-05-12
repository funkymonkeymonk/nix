# Service module option tests using evalModules
# Tests ollama, vane, and openclaw options without requiring platform-specific modules
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

  # Evaluate ollama options with defaults
  ollamaDefaultEval =
    (lib.evalModules {
      modules =
        stubModules
        ++ [
          {
            config.myConfig.ollama.enable = false;
          }
        ];
    }).config.myConfig.ollama;

  # Evaluate ollama with custom values
  ollamaCustomEval =
    (lib.evalModules {
      modules =
        stubModules
        ++ [
          {
            config.myConfig.ollama = {
              enable = true;
              host = "0.0.0.0";
              port = 12345;
              models = ["llama3.2" "qwen3:4b"];
              acceleration = "metal";
            };
          }
        ];
    }).config.myConfig.ollama;

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
        ../modules/services/openclaw/default.nix
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
          options.launchd = lib.mkOption {
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
  # Test ollama option defaults
  ollamaOptionsTest =
    pkgs.runCommand "test-ollama-options"
    {}
    ''
      echo "=== Testing Ollama Option Defaults ==="

      ${
        if !ollamaDefaultEval.enable
        then ''echo "  enable default = false: OK"''
        else ''echo "  enable should default to false!"; exit 1''
      }

      ${
        if ollamaDefaultEval.host == "127.0.0.1"
        then ''echo "  host default = 127.0.0.1: OK"''
        else ''echo "  host should default to 127.0.0.1!"; exit 1''
      }

      ${
        if ollamaDefaultEval.port == 11434
        then ''echo "  port default = 11434: OK"''
        else ''echo "  port should default to 11434!"; exit 1''
      }

      ${
        if ollamaDefaultEval.models == []
        then ''echo "  models default = []: OK"''
        else ''echo "  models should default to empty list!"; exit 1''
      }

      ${
        if ollamaDefaultEval.acceleration == null
        then ''echo "  acceleration default = null: OK"''
        else ''echo "  acceleration should default to null!"; exit 1''
      }

      ${
        if ollamaDefaultEval.environmentFile == null
        then ''echo "  environmentFile default = null: OK"''
        else ''echo "  environmentFile should default to null!"; exit 1''
      }

      echo "All ollama option defaults verified"
      touch $out
    '';

  # Test ollama custom option values
  ollamaCustomOptionsTest =
    pkgs.runCommand "test-ollama-custom-options"
    {}
    ''
      echo "=== Testing Ollama Custom Options ==="

      ${
        if ollamaCustomEval.enable
        then ''echo "  enable = true: OK"''
        else ''echo "  enable should be true!"; exit 1''
      }

      ${
        if ollamaCustomEval.host == "0.0.0.0"
        then ''echo "  host = 0.0.0.0: OK"''
        else ''echo "  host should be 0.0.0.0!"; exit 1''
      }

      ${
        if ollamaCustomEval.port == 12345
        then ''echo "  port = 12345: OK"''
        else ''echo "  port should be 12345!"; exit 1''
      }

      ${
        if builtins.length ollamaCustomEval.models == 2
        then ''echo "  models count = 2: OK"''
        else ''echo "  models should have 2 entries!"; exit 1''
      }

      ${
        if ollamaCustomEval.acceleration == "metal"
        then ''echo "  acceleration = metal: OK"''
        else ''echo "  acceleration should be metal!"; exit 1''
      }

      echo "All ollama custom options verified"
      touch $out
    '';

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
}
