# vllm-mlx inference server tests
# Validates option defaults, custom values, launchd daemon wiring, and the
# MegamanX target's Gemma 4 configuration.
{pkgs, ...}: let
  inherit (pkgs) lib;
  stubs = import ./stubs.nix {inherit pkgs;};

  vllmMlxModule = ../modules/services/vllm-mlx/darwin.nix;

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

  vllmMlxDefaults =
    (lib.evalModules {
      modules = stubs.vllmMlx;
    }).config.myConfig.vllmMlx;

  vllmMlxCustom =
    (lib.evalModules {
      modules =
        stubs.vllmMlx
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
              lockAdmission = "fail_fast";
              timeout = 300;
              logLevel = "DEBUG";
            };
          }
        ];
    }).config.myConfig.vllmMlx;

  # Evaluate the launchd wiring for an enabled server. `extra` is merged into
  # myConfig.vllmMlx so tests can flip individual knobs.
  mkLaunchdEval = extra:
    (lib.evalModules {
      modules =
        stubs.vllmMlx
        ++ [
          {
            config.myConfig.users = [{name = "monkey";}];
            config.myConfig.vllmMlx =
              {
                enable = true;
                models.test-model.path = "mlx-community/test-model-4bit";
              }
              // extra;
          }
        ];
    })
    .config;

  launchdDefault = mkLaunchdEval {};
  launchdFailFast = mkLaunchdEval {lockAdmission = "fail_fast";};

  # Evaluate the actual MegamanX target to verify its vllm-mlx config
  megamanxEval = lib.evalModules {
    modules =
      stubs.base
      ++ stubs.darwinService
      ++ stubs.onepassword
      ++ [
        ../modules/services/vllm-mlx/darwin-instances-options.nix
        vllmMlxModule
        ../modules/services/vllm-mlx/darwin-instances-config.nix
        ../modules/services/bifrost/darwin.nix
        ../modules/services/vane/darwin.nix
        ../modules/services/searxng/darwin.nix
        ../modules/services/caddy/darwin.nix
        ../modules/services/prometheus/darwin.nix
        ../modules/services/node-exporter/darwin.nix
        {
          options.system.stateVersion = lib.mkOption {
            type = lib.types.anything;
            default = 4;
          };
          options.system.primaryUser = lib.mkOption {
            type = lib.types.anything;
            default = "monkey";
          };
        }
        (import ../hosts/megamanx/default.nix)
        {
          # pkgs comes from stubs.base (moduleArgsStub); only add what the
          # host file needs beyond it.
          config._module.args = {
            mkUser = mkUserStub;
            inputs = stubInputs;
          };
        }
      ];
  };
  megamanxVllmMlx = megamanxEval.config.myConfig.vllmMlx;
  megamanxVllmMlxInstances = megamanxEval.config.myConfig.vllmMlxInstances;
  megamanxVllmDaemon = megamanxEval.config.launchd.daemons."vllm-mlx".serviceConfig;
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
        if vllmMlxDefaults.lockAdmission == "wait"
        then ''echo "  lockAdmission default = wait: OK"''
        else ''echo "  lockAdmission should default to wait (queue instead of 503)!"; exit 1''
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
        if vllmMlxCustom.reasoningParser == "gemma4"
        then ''echo "  reasoningParser = gemma4: OK"''
        else ''echo "  reasoningParser should be gemma4!"; exit 1''
      }

      ${
        if vllmMlxCustom.lockAdmission == "fail_fast"
        then ''echo "  lockAdmission = fail_fast: OK"''
        else ''echo "  lockAdmission should be fail_fast!"; exit 1''
      }

      echo ""
      echo "All vllm-mlx option tests passed"
      touch $out
    '';

  # Verify the launchd daemon wiring: lock-admission env var and durable log
  # paths (not /tmp, which macOS cleans every 3 days).
  vllmMlxLaunchdTest = pkgs.runCommand "test-vllm-mlx-launchd" {} ''
    echo "=== Testing vllm-mlx launchd Wiring ==="

    ${
      let
        env = launchdDefault.launchd.daemons."vllm-mlx".serviceConfig.EnvironmentVariables;
      in
        if env.VLLM_MLX_SIMPLE_ENGINE_LOCK_ADMISSION == "wait"
        then ''echo "  lock admission env = wait: OK"''
        else ''echo "  FAIL: VLLM_MLX_SIMPLE_ENGINE_LOCK_ADMISSION should be wait, got ${env.VLLM_MLX_SIMPLE_ENGINE_LOCK_ADMISSION or "(unset)"}"; exit 1''
    }
    ${
      let
        env = launchdFailFast.launchd.daemons."vllm-mlx".serviceConfig.EnvironmentVariables;
      in
        if env.VLLM_MLX_SIMPLE_ENGINE_LOCK_ADMISSION == "fail_fast"
        then ''echo "  lock admission env = fail_fast (opt-out): OK"''
        else ''echo "  FAIL: VLLM_MLX_SIMPLE_ENGINE_LOCK_ADMISSION should be fail_fast, got ${env.VLLM_MLX_SIMPLE_ENGINE_LOCK_ADMISSION or "(unset)"}"; exit 1''
    }
    ${
      let
        sc = launchdDefault.launchd.daemons."vllm-mlx".serviceConfig;
      in
        if sc.StandardOutPath == "/Users/monkey/Library/Logs/vllm-mlx/server.log"
        then ''echo "  server stdout log durable: OK"''
        else ''echo "  FAIL: StandardOutPath should be /Users/monkey/Library/Logs/vllm-mlx/server.log, got ${sc.StandardOutPath}"; exit 1''
    }
    ${
      let
        sc = launchdDefault.launchd.daemons."vllm-mlx".serviceConfig;
      in
        if sc.StandardErrorPath == "/Users/monkey/Library/Logs/vllm-mlx/server.error.log"
        then ''echo "  server stderr log durable: OK"''
        else ''echo "  FAIL: StandardErrorPath should be /Users/monkey/Library/Logs/vllm-mlx/server.error.log, got ${sc.StandardErrorPath}"; exit 1''
    }
    ${
      let
        sc = launchdDefault.launchd.daemons."vllm-mlx-warmup".serviceConfig;
      in
        if sc.StandardOutPath == "/Users/monkey/Library/Logs/vllm-mlx/warmup.log" && sc.StandardErrorPath == "/Users/monkey/Library/Logs/vllm-mlx/warmup.error.log"
        then ''echo "  warmup logs durable: OK"''
        else ''echo "  FAIL: warmup logs should live in /Users/monkey/Library/Logs/vllm-mlx/"; exit 1''
    }
    ${
      if launchdDefault.myConfig.serviceRegistry.vllm-mlx.errorLog == "/Users/monkey/Library/Logs/vllm-mlx/server.error.log"
      then ''echo "  serviceRegistry errorLog durable: OK"''
      else ''echo "  FAIL: serviceRegistry errorLog should point at the durable log path"; exit 1''
    }

    echo ""
    echo "All vllm-mlx launchd tests passed"
    touch $out
  '';

  # Verify the actual MegamanX target config targets Qwen 3.8 with qwen3 parsers
  # and that its serving limits line up with the pi client's expectations.
  megamanxVllmMlxTest = pkgs.runCommand "test-megamanx-vllm" {} ''
    echo "=== Testing MegamanX vllm-mlx Configuration ==="
    echo ""
    ${
      let
        hasModel = builtins.elem "qwen3.8-27b" (builtins.attrNames megamanxVllmMlx.models);
        modelPath =
          if hasModel
          then megamanxVllmMlx.models."qwen3.8-27b".path
          else null;
      in
        if hasModel && modelPath == "mlx-community/Qwen3.8-27B-8bit"
        then ''echo "  model = Qwen3.8-27B-8bit: OK"''
        else ''echo "  FAIL: model should be mlx-community/Qwen3.8-27B-8bit, got ${toString modelPath}"; exit 1''
    }
    ${
      let
        hasGemmaInstance = builtins.hasAttr "gemma" megamanxVllmMlxInstances;
        gemmaInstance = megamanxVllmMlxInstances.gemma or {};
        hasE4b = builtins.elem "gemma4-e4b" (builtins.attrNames (gemmaInstance.models or {}));
        e4bPath =
          if hasE4b
          then gemmaInstance.models."gemma4-e4b".path
          else null;
      in
        if hasGemmaInstance && hasE4b && e4bPath == "mlx-community/gemma-4-e4b-it-4bit"
        then ''echo "  gemma instance e4b model = gemma-4-e4b-it-4bit: OK"''
        else ''echo "  FAIL: gemma instance should serve mlx-community/gemma-4-e4b-it-4bit, got ${toString e4bPath}"; exit 1''
    }
    ${
      let
        gemmaInstance = megamanxVllmMlxInstances.gemma or {};
      in
        if gemmaInstance.toolCallParser or null == "gemma4"
        then ''echo "  gemma instance toolCallParser = gemma4: OK"''
        else ''echo "  FAIL: gemma instance toolCallParser should be gemma4, got ${toString gemmaInstance.toolCallParser}"; exit 1''
    }
    ${
      let
        gemmaInstance = megamanxVllmMlxInstances.gemma or {};
      in
        if gemmaInstance.enableContinuousBatching or false
        then ''echo "  gemma instance enableContinuousBatching = true: OK"''
        else ''echo "  FAIL: gemma instance should use BatchedEngine for concurrent requests"; exit 1''
    }
    ${
      if megamanxVllmMlx.toolCallParser == "qwen"
      then ''echo "  toolCallParser = qwen: OK"''
      else ''echo "  FAIL: toolCallParser should be qwen, got ${toString megamanxVllmMlx.toolCallParser}"; exit 1''
    }
    ${
      if megamanxVllmMlx.reasoningParser == "qwen3"
      then ''echo "  reasoningParser = qwen3: OK"''
      else ''echo "  FAIL: reasoningParser should be qwen3, got ${toString megamanxVllmMlx.reasoningParser}"; exit 1''
    }
    ${
      # pi advertises maxTokens = 131072 for the bifrost model; the server KV
      # cap must match or long sessions silently rotate out the system prompt
      # and tool definitions.
      if megamanxVllmMlx.maxKvSize == 131072
      then ''echo "  maxKvSize = 131072 (matches pi maxTokens): OK"''
      else ''echo "  FAIL: maxKvSize should be 131072 to match pi maxTokens, got ${toString megamanxVllmMlx.maxKvSize}"; exit 1''
    }
    ${
      if megamanxVllmMlx.memoryBudgetGb == 64
      then ''echo "  memoryBudgetGb = 64: OK"''
      else ''echo "  FAIL: memoryBudgetGb should be 64, got ${toString megamanxVllmMlx.memoryBudgetGb}"; exit 1''
    }
    ${
      # pi's provider timeout is 600s; the server must not kill requests first.
      if megamanxVllmMlx.timeout == 600
      then ''echo "  timeout = 600 (matches pi provider timeout): OK"''
      else ''echo "  FAIL: timeout should be 600 to match pi provider timeoutMs, got ${toString megamanxVllmMlx.timeout}"; exit 1''
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
    ${
      # Queued admission is the whole fix for the 503 text_generation_busy
      # storms that broke agent tool use — assert it on the real target.
      if megamanxVllmDaemon.EnvironmentVariables.VLLM_MLX_SIMPLE_ENGINE_LOCK_ADMISSION == "wait"
      then ''echo "  daemon lock admission = wait: OK"''
      else ''echo "  FAIL: daemon should queue concurrent requests (VLLM_MLX_SIMPLE_ENGINE_LOCK_ADMISSION=wait)"; exit 1''
    }
    echo ""
    echo "All MegamanX vllm-mlx tests passed"
    touch $out
  '';
}
