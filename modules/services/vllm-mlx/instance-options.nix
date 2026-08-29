# Per-instance options for vllm-mlx.
# Reused by the default instance (myConfig.vllmMlx) and any extra
# named instances (myConfig.vllmMlxInstances).
{lib, ...}: {
  options = {
    enable = lib.mkEnableOption "vllm-mlx inference server instance";

    package = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Override the vllm-mlx binary path. When null, uses the Nix-packaged vllm-mlx (built with Metal GPU support via prebuilt PyPI wheels). Set to an external binary (e.g. uv-installed) only for testing upstream fixes or when the Nix package version is too old.";
    };

    server = {
      host = lib.mkOption {
        type = lib.types.str;
        default = "0.0.0.0";
        description = "Bind address for vllm-mlx server";
      };
      port = lib.mkOption {
        type = lib.types.port;
        default = 8300;
        description = "Bind port for vllm-mlx server";
      };
    };

    memoryBudgetGb = lib.mkOption {
      type = lib.types.ints.unsigned;
      default = 24;
      description = "Memory budget in GB for model loading. Idle models are evicted under this budget.";
    };

    contention = lib.mkOption {
      type = lib.types.enum ["wait" "preempt" "fail"];
      default = "preempt";
      description = "Behavior when a requested model is not loaded and memory is full: wait (queue), preempt (evict current), or fail (reject).";
    };

    models = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule {
        options = {
          path = lib.mkOption {
            type = lib.types.str;
            description = "Model path or HuggingFace ID (e.g., mlx-community/gemma-4-12B-it-qat-4bit)";
          };
          type = lib.mkOption {
            type = lib.types.enum ["lm" "multimodal" "embedding"];
            default = "lm";
            description = "Model type: lm (text), multimodal (vision), or embedding";
          };
          estimatedMemoryGb = lib.mkOption {
            type = lib.types.nullOr lib.types.ints.positive;
            default = null;
            description = "Estimated memory in GB for non-local (HuggingFace) models. Required for registry-backed loading so eviction remains deterministic.";
          };
          preload = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Load this model into memory at server startup. Useful for keeping frequently-used models resident.";
          };
        };
      });
      default = {};
      description = "Model registry. Each key is a model alias used in API requests. vllm-mlx lazily loads models on first use.";
    };

    enableAutoToolChoice = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable automatic tool calling. The model decides when to use tools based on the prompt.";
    };

    toolCallParser = lib.mkOption {
      type = lib.types.nullOr (lib.types.enum ["auto" "mistral" "qwen" "qwen3_coder" "llama" "hermes" "harmony" "gpt-oss" "deepseek" "kimi" "granite" "nemotron" "xlam" "functionary" "gemma4" "glm47" "minimax"]);
      default = null;
      description = "Tool call parser format. Must match model's training format. 'gemma4' for Gemma 4, 'qwen' for Qwen2/3.";
    };

    reasoningParser = lib.mkOption {
      type = lib.types.nullOr (lib.types.enum ["qwen3" "deepseek_r1" "gpt_oss" "harmony" "gemma4" "glm4" "mistral" "poolside_v1"]);
      default = null;
      description = "Reasoning parser for extracting thinking/reasoning content from model output. 'qwen3' for Qwen3, 'gemma4' for Gemma 4.";
    };

    lockAdmission = lib.mkOption {
      type = lib.types.enum ["wait" "fail_fast"];
      default = "wait";
      description = "Admission policy when a request arrives while another generation holds the serialized engine lock. 'wait' queues requests (correct for a single-user local server behind agent traffic, where parallel requests are normal); 'fail_fast' rejects with 503 text_generation_busy. Maps to VLLM_MLX_SIMPLE_ENGINE_LOCK_ADMISSION.";
    };

    logDir = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Directory for launchd stdout/stderr logs. Defaults to ~/Library/Logs/vllm-mlx for the default instance, or ~/Library/Logs/vllm-mlx/<name> for extra instances. Do not use /tmp: macOS cleans it every 3 days and launchd keeps writing to the deleted inode, silently discarding all server logs.";
    };

    maxKvSize = lib.mkOption {
      type = lib.types.nullOr lib.types.ints.positive;
      default = null;
      description = "Maximum KV cache size per sequence (number of tokens). When set, oldest tokens roll off to prevent unbounded memory growth.";
    };

    timeout = lib.mkOption {
      type = lib.types.ints.unsigned;
      default = 120;
      description = "Request timeout in seconds.";
    };

    logLevel = lib.mkOption {
      type = lib.types.enum ["DEBUG" "INFO" "WARNING" "ERROR"];
      default = "INFO";
      description = "Server log level.";
    };

    enableMetrics = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Expose Prometheus metrics on /metrics endpoint.";
    };

    enableContinuousBatching = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable continuous batching (BatchedEngine) for concurrent requests. Allows prefix caching across turns but adds per-request overhead.";
    };

    enablePrefixCache = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable prefix caching in BatchedEngine mode. Reuses KV cache blocks for common prompt prefixes across requests/conversations. Requires --continuous-batching.";
    };

    chunkedPrefillTokens = lib.mkOption {
      type = lib.types.nullOr (lib.types.addCheck lib.types.int (x: x >= 0));
      default = null;
      description = "Chunk size for prefill processing in BatchedEngine mode (0 disables chunked prefill). May be needed to avoid crashes with large prompts when prefix caching is enabled.";
    };

    enableMtp = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable Multi-Token Prediction (MTP) for models with built-in MTP heads such as Qwen3.8. Can significantly increase generation throughput.";
    };

    mtpNumDraftTokens = lib.mkOption {
      type = lib.types.ints.positive;
      default = 1;
      description = "Number of draft tokens to predict per MTP step. Higher values increase speed when acceptance rate is high.";
    };

    mtpOptimistic = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Skip MTP acceptance verification for maximum speed. May produce ~5-10% incorrect tokens; use with caution.";
    };

    mllmDraftModel = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        Path or HuggingFace repo ID of an mlx-vlm MLLM draft/assistant model.
        Used for speculative decoding with --mllm-draft-kind. In vllm-mlx
        0.4.1 this path is specific to Gemma 4 assistant drafters; it does
        not load Qwen3.5/3.6/3.8 MTP weights. For Qwen3 MTP, enable
        `enableMtp` and use an MTP-capable checkpoint instead.

        Note: --mllm-draft-model is incompatible with --models-config, so
        setting this option forces single-model mode for this instance (only
        the primary preloaded model is served).
      '';
    };

    mllmDraftKind = lib.mkOption {
      type = lib.types.nullOr (lib.types.enum ["mtp"]);
      default = null;
      description = "mlx-vlm draft kind for --mllm-draft-model. Defaults to 'mtp' when mllmDraftModel is set.";
    };

    mllmDraftBlockSize = lib.mkOption {
      type = lib.types.nullOr lib.types.ints.positive;
      default = null;
      description = "Draft block size passed to mlx-vlm for --mllm-draft-model. Defaults to 3 when mllmDraftModel is set.";
    };
  };
}
