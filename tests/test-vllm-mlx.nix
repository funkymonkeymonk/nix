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
    jj-autosync = {
      enable = true;
      username = name;
    };
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
        (import ../targets/MegamanX/default.nix)
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

      echo ""
      echo "All vllm-mlx option tests passed"
      touch $out
    '';

  # Verify the actual MegamanX target config targets Qwen3.6 with qwen tool calling
  megamanxVllmMlxTest = pkgs.runCommand "test-megamanx-vllm" {} ''
    echo "=== Testing MegamanX vllm-mlx Configuration ==="
    echo ""
    ${
      let
        hasModel = builtins.elem "qwen3.6-27b" (builtins.attrNames megamanxVllmMlx.models);
        modelPath =
          if hasModel
          then megamanxVllmMlx.models."qwen3.6-27b".path
          else null;
      in
        if hasModel && modelPath == "mlx-community/Qwen3.6-27B-4bit"
        then ''echo "  model = Qwen3.6-27B-4bit: OK"''
        else ''echo "  FAIL: model should be mlx-community/Qwen3.6-27B-4bit, got ${toString modelPath}"; exit 1''
    }
    ${
      if megamanxVllmMlx.toolCallParser == "qwen"
      then ''echo "  toolCallParser = qwen: OK"''
      else ''echo "  FAIL: toolCallParser should be qwen, got ${toString megamanxVllmMlx.toolCallParser}"; exit 1''
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
    echo ""
    echo "All MegamanX vllm-mlx tests passed"
    touch $out
  '';
}
