# Service module option tests using evalModules
# Tests vane options without requiring platform-specific modules
{
  pkgs,
  self ? null,
  ...
}: let
  inherit (pkgs) lib;

  # Shared stub modules for evalModules
  # vane.nix declares its own options (modules/services/vane/darwin.nix), so it's
  # imported directly here rather than relying on modules/common/options.nix.
  stubModules = [
    ../modules/common/options.nix
    ../modules/services/vane/darwin.nix
    {
      options.nixpkgs.hostPlatform = lib.mkOption {
        type = lib.types.anything;
        default = {inherit (pkgs.stdenv.hostPlatform) system;};
      };
      options.launchd.daemons = lib.mkOption {
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
              searxngUrl = "http://my-searxng:9090";
              defaultModel = "llama3.2";
              embeddingModel = "mxbai-embed-large";
              autoStart = true;
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
      options.launchd.daemons = lib.mkOption {
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
    .daemons
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
    .daemons
    .vane
    .serviceConfig;

  # Evaluate the real MegamanX target to verify it doesn't carry a dangling
  # reference to an Ollama service that no longer runs on that host (Ollama
  # support was removed entirely — see modules/services/ollama removal).
  megamanxVaneConfig =
    if self != null
    then self.darwinConfigurations.MegamanX.config.myConfig.vane
    else null;
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
        if !vaneDefaultEval.autoStart
        then ''echo "  autoStart default = false: OK"''
        else ''echo "  autoStart should default to false!"; exit 1''
      }

      ${
        if vaneDefaultEval.searxngUrl == null
        then ''echo "  searxngUrl default = null: OK"''
        else ''echo "  searxngUrl should default to null!"; exit 1''
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
        if vaneCustomEval.searxngUrl == "http://my-searxng:9090"
        then ''echo "  searxngUrl = http://my-searxng:9090: OK"''
        else ''echo "  searxngUrl should be http://my-searxng:9090!"; exit 1''
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

      echo "All vane custom options verified"
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

  # Verify the real MegamanX host config has no dangling Ollama wiring.
  # Ollama was fully removed from this repo (no host manages it via Nix
  # anymore — vllm-mlx + Bifrost handle all local inference), so a host
  # that still points vane.ollamaUrl/embeddingModel at Ollama would be
  # pointing at a service that no Nix module actually provisions.
  vaneMegamanxNoOllamaWiringTest =
    if megamanxVaneConfig == null
    then pkgs.runCommand "test-vane-megamanx-no-ollama-wiring" {} "touch $out"
    else
      pkgs.runCommand "test-vane-megamanx-no-ollama-wiring"
      {}
      ''
        echo "=== Testing MegamanX Vane has no dangling Ollama wiring ==="

        ${
          if megamanxVaneConfig.ollamaUrl == null
          then ''echo "  vane.ollamaUrl = null: OK"''
          else ''echo "  vane.ollamaUrl should be null (no Ollama service runs on MegamanX), got ${megamanxVaneConfig.ollamaUrl}"; exit 1''
        }

        ${
          if megamanxVaneConfig.embeddingModel == null
          then ''echo "  vane.embeddingModel = null: OK"''
          else ''echo "  vane.embeddingModel should be null, got ${megamanxVaneConfig.embeddingModel}"; exit 1''
        }

        echo "MegamanX vane has no dangling Ollama wiring"
        touch $out
      '';
}
