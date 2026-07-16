# vllm-mlx inference server option tests
# Validates option defaults and custom values
{pkgs, ...}: let
  inherit (pkgs) lib;

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

  # Stub mkUser matching the flake.nix helper shape
  mkUserStub = name: email: {
    users = [
      {
        inherit name email;
        fullName = "Will Weaver";
        isAdmin = true;
        sshIncludes = [];
      }
    ];
    onepassword.enable = true;
    opencode = {
      enable = true;
      model = "opencode/big-pickle";
    };
    claude-code = {enable = false;};
    llmClient.rtk.enable = true;
  };
  stubInputs = {superpowers = "/stub/superpowers";};

  # Evaluate the actual MegamanX target to verify its vllm-mlx config
  megamanxVllmMlx =
    (lib.evalModules {
      modules = [
        ../modules/common/options.nix
        (import ../hosts/megamanx/default.nix)
        {
          options.nixpkgs.hostPlatform = lib.mkOption {
            type = lib.types.anything;
            default = {inherit (pkgs.stdenv.hostPlatform) system;};
          };
          options.system.stateVersion = lib.mkOption {
            type = lib.types.anything;
            default = 4;
          };
          options.system.primaryUser = lib.mkOption {
            type = lib.types.anything;
            default = "monkey";
          };
          options.system.activationScripts = lib.mkOption {
            type = lib.types.anything;
            default = {};
          };
          # Stubs for nix-darwin options imported by workstation archetype
          options.launchd = lib.mkOption {
            type = lib.types.anything;
            default = {};
          };
          options.homebrew = lib.mkOption {
            type = lib.types.anything;
            default = {};
          };
        }
        {
          config._module.args = {
            inherit pkgs;
            mkUser = mkUserStub;
            inputs = stubInputs;
          };
        }
      ];
    }).config.myConfig.vllmMlx;

  vllmMlxDefaults =
    (lib.evalModules {
      modules = stubModules;
    }).config.myConfig.vllmMlx;

  vllmMlxCustom =
    (lib.evalModules {
      modules =
        stubModules
        ++ [
          {
            config.myConfig.vllmMlx = {
              enable = true;
              server = {
                host = "127.0.0.1";
                port = 9300;
              };
              memoryBudgetGb = 32;
              contention = "wait";
              models = {
                test-model = {
                  path = "mlx-community/test-model-4bit";
                  type = "lm";
                };
              };
              enableAutoToolChoice = true;
              toolCallParser = "gemma4";
              reasoningParser = "gemma4";
              timeout = 300;
              logLevel = "DEBUG";
            };
          }
        ];
    }).config.myConfig.vllmMlx;
in {
  vllmMlxOptionsTest =
    pkgs.runCommand "test-vllm-mlx-options"
    {}
    ''
      echo "=== Testing vllm-mlx Option Defaults ==="

      ${
        if !vllmMlxDefaults.enable
        then ''echo "  enable default = false: OK"''
        else ''echo "  enable should default to false!"; exit 1''
      }

      ${
        if vllmMlxDefaults.server.host == "0.0.0.0"
        then ''echo "  server.host default = 0.0.0.0: OK"''
        else ''echo "  server.host should default to 0.0.0.0!"; exit 1''
      }

      ${
        if vllmMlxDefaults.server.port == 8300
        then ''echo "  server.port default = 8300: OK"''
        else ''echo "  server.port should default to 8300!"; exit 1''
      }

      ${
        if vllmMlxDefaults.memoryBudgetGb == 24
        then ''echo "  memoryBudgetGb default = 24: OK"''
        else ''echo "  memoryBudgetGb should default to 24!"; exit 1''
      }

      ${
        if vllmMlxDefaults.contention == "preempt"
        then ''echo "  contention default = preempt: OK"''
        else ''echo "  contention should default to preempt!"; exit 1''
      }

      ${
        if vllmMlxDefaults.enableAutoToolChoice
        then ''echo "  enableAutoToolChoice default = true: OK"''
        else ''echo "  enableAutoToolChoice should default to true!"; exit 1''
      }

      ${
        if vllmMlxDefaults.toolCallParser == null
        then ''echo "  toolCallParser default = null: OK"''
        else ''echo "  toolCallParser should default to null!"; exit 1''
      }

      ${
        if vllmMlxDefaults.reasoningParser == null
        then ''echo "  reasoningParser default = null: OK"''
        else ''echo "  reasoningParser should default to null!"; exit 1''
      }

      ${
        if vllmMlxDefaults.timeout == 120
        then ''echo "  timeout default = 120: OK"''
        else ''echo "  timeout should default to 120!"; exit 1''
      }

      ${
        if vllmMlxDefaults.logLevel == "INFO"
        then ''echo "  logLevel default = INFO: OK"''
        else ''echo "  logLevel should default to INFO!"; exit 1''
      }

      echo ""
      echo "=== Testing vllm-mlx Custom Options ==="

      ${
        if vllmMlxCustom.enable == true
        then ''echo "  enable = true: OK"''
        else ''echo "  enable should be true!"; exit 1''
      }

      ${
        if vllmMlxCustom.server.host == "127.0.0.1"
        then ''echo "  server.host = 127.0.0.1: OK"''
        else ''echo "  server.host should be 127.0.0.1!"; exit 1''
      }

      ${
        if vllmMlxCustom.server.port == 9300
        then ''echo "  server.port = 9300: OK"''
        else ''echo "  server.port should be 9300!"; exit 1''
      }

      ${
        if vllmMlxCustom.memoryBudgetGb == 32
        then ''echo "  memoryBudgetGb = 32: OK"''
        else ''echo "  memoryBudgetGb should be 32!"; exit 1''
      }

      ${
        if vllmMlxCustom.contention == "wait"
        then ''echo "  contention = wait: OK"''
        else ''echo "  contention should be wait!"; exit 1''
      }

      ${
        if vllmMlxCustom.models.test-model.path == "mlx-community/test-model-4bit"
        then ''echo "  models.test-model.path = mlx-community/test-model-4bit: OK"''
        else ''echo "  models.test-model.path should be mlx-community/test-model-4bit!"; exit 1''
      }

      ${
        if vllmMlxCustom.toolCallParser == "gemma4"
        then ''echo "  toolCallParser = gemma4: OK"''
        else ''echo "  toolCallParser should be gemma4!"; exit 1''
      }

      ${
        if vllmMlxCustom.reasoningParser == null
        then ''echo "  reasoningParser = null: OK"''
        else ''echo "  reasoningParser should be null!"; exit 1''
      }

      echo ""
      echo "All vllm-mlx option tests passed"
      touch $out
    '';

  # Verify the actual MegamanX target config targets Gemma 4 with gemma4 parsers
  megamanxVllmMlxTest = pkgs.runCommand "test-megamanx-vllm" {} ''
    echo "=== Testing MegamanX vllm-mlx Configuration ==="
    echo ""
    ${
      let
        hasModel = builtins.elem "gemma4-31b" (builtins.attrNames megamanxVllmMlx.models);
        modelPath =
          if hasModel
          then megamanxVllmMlx.models."gemma4-31b".path
          else null;
      in
        if hasModel && modelPath == "mlx-community/gemma-4-31b-it-4bit"
        then ''echo "  model = gemma-4-31b-it-4bit: OK"''
        else ''echo "  FAIL: model should be mlx-community/gemma-4-31b-it-4bit, got ${toString modelPath}"; exit 1''
    }
    ${
      let
        hasE4b = builtins.elem "gemma4-e4b" (builtins.attrNames megamanxVllmMlx.models);
        e4bPath =
          if hasE4b
          then megamanxVllmMlx.models."gemma4-e4b".path
          else null;
      in
        if hasE4b && e4bPath == "mlx-community/gemma-4-e4b-it-4bit"
        then ''echo "  e4b model = gemma-4-e4b-it-4bit: OK"''
        else ''echo "  FAIL: e4b model should be mlx-community/gemma-4-e4b-it-4bit, got ${toString e4bPath}"; exit 1''
    }
    ${
      if megamanxVllmMlx.toolCallParser == "gemma4"
      then ''echo "  toolCallParser = gemma4: OK"''
      else ''echo "  FAIL: toolCallParser should be gemma4, got ${toString megamanxVllmMlx.toolCallParser}"; exit 1''
    }
    ${
      if megamanxVllmMlx.reasoningParser == null
      then ''echo "  reasoningParser = null: OK"''
      else ''echo "  FAIL: reasoningParser should be null, got ${toString megamanxVllmMlx.reasoningParser}"; exit 1''
    }
    ${
      if megamanxVllmMlx.maxKvSize == 65536
      then ''echo "  maxKvSize = 65536: OK"''
      else ''echo "  FAIL: maxKvSize should be 65536, got ${toString megamanxVllmMlx.maxKvSize}"; exit 1''
    }
    ${
      if megamanxVllmMlx.memoryBudgetGb == 90
      then ''echo "  memoryBudgetGb = 90: OK"''
      else ''echo "  FAIL: memoryBudgetGb should be 90, got ${toString megamanxVllmMlx.memoryBudgetGb}"; exit 1''
    }
    ${
      if megamanxVllmMlx.enableAutoToolChoice
      then ''echo "  enableAutoToolChoice = true: OK"''
      else ''echo "  FAIL: enableAutoToolChoice should be true"; exit 1''
    }
    ${
      if megamanxVllmMlx.enable
      then ''echo "  enable = true: OK"''
      else ''echo "  FAIL: vllmMlx should be enabled"; exit 1''
    }
    echo ""
    echo "All MegamanX vllm-mlx tests passed"
    touch $out
  '';
}
