# vllm-mlx — vLLM-style inference server for Apple Silicon
# Built from GitHub source with Metal-enabled mlx.
# Gradio is removed (UI optional). mlx-vlm comes from the overlay
# at version 0.6.4 because nixpkgs 0.4.4 lacks Gemma 4 support.
{
  lib,
  python3Packages,
  fetchFromGitHub,
  mlx-embeddings,
  mlx-vlm,
}:
python3Packages.buildPythonApplication rec {
  pname = "vllm-mlx";
  version = "0.4.1-unstable-2026-08-15";
  pyproject = true;

  # Latest main (post-v0.4.1) including the merged PR #673 terminal
  # finish_reason fix (#672) and engine-side fixes (#681, #629).
  # Also includes the Gemma 4 fallback parser (#622) for e4b's
  # non-canonical tool call formats.
  src = fetchFromGitHub {
    owner = "waybarrios";
    repo = "vllm-mlx";
    rev = "61c78dc04099932192f9a195fb9cfc8bb8835c72";
    hash = "sha256-6pX+xBrsZqAT/MSDkCY6tuzFCXASUm9aC+QC5VyA72Q=";
  };

  nativeBuildInputs = with python3Packages; [
    setuptools
    wheel
    pythonRelaxDepsHook
  ];

  # PR #673 is now merged upstream (commit 61c78dc).  v0.4.1 includes
  # the engine-side fixes (#681, #629) and the Gemma 4 fallback parser
  # (#622).  The patch below remains unmerged upstream:
  patches = [
    # Allow system-prompt KV cache snapshots when the model mixes plain KVCache,
    # RotatingKVCache (e.g. Gemma 4), or ArraysCache (MLLM text routing for
    # Qwen3.5/3.6/3.8). The upstream 0.4.1 probe disables snapshots for any
    # non-KVCache class and does not capture RotatingKVCache cursor metadata,
    # forcing a full re-prefill on every turn. This patch captures both state
    # and meta_state and uses _cache_class_is_system_snapshot_safe for the
    # MLLM text-routing probe.
    ./snapshot-rotating-kv-cache.patch
  ];

  pythonRemoveDeps = [
    "gradio"
    "opencv-python"
  ];

  propagatedBuildInputs = with python3Packages;
    [
      mlx
      mlx-lm
      transformers
      tokenizers
      huggingface-hub
      numpy
      pillow
      tqdm
      pyyaml
      requests
      tabulate
      opencv4
      torchvision
      torch
      psutil
      fastapi
      starlette
      uvicorn
      prometheus-client
      mcp
      jsonschema
      lm-format-enforcer
      typing-extensions
      openai
      httpx
      aiohttp
      tiktoken
    ]
    ++ [mlx-embeddings mlx-vlm];

  # Patch bind_generation_streams to use set_generation_stream() when available,
  # instead of replacing the function with a raw Stream object via setattr.
  # Our patched mlx-lm 0.31.3 makes generation_stream a function with a
  # thread-local backing; clobbering it with setattr breaks inference.
  #
  # Also patch Gemma4 tool parser to treat <turn|> as a stop token. Gemma 4's
  # tokenizer defines eot_token = "<turn|>" but vllm-mlx only uses the default
  # eos_token_id for stopping, causing the model to emit <turn|> as text and
  # continue generating in an infinite loop.
  #
  # Also strip <turn|> from output text via SPECIAL_TOKENS_PATTERN so it
  # doesn't appear in API responses (it's an internal control token).
  postPatch = ''
    substituteInPlace vllm_mlx/mlx_streams.py \
      --replace-fail 'if hasattr(module, "generation_stream"):' 'if hasattr(module, "set_generation_stream"):' \
      --replace-fail 'setattr(module, "generation_stream", default_stream)' 'module.set_generation_stream(default_stream)'

    substituteInPlace vllm_mlx/tool_parsers/gemma4_tool_parser.py \
      --replace-fail 'extra_stop_tokens = ["<|tool_response>"]' 'extra_stop_tokens = ["<|tool_response>", "<turn|>"]'

    substituteInPlace vllm_mlx/api/utils.py \
      --replace-fail 'r"<\|channel\|>|<\|message\|>|<\|start\|>|<\|return\|>|<\|call\|>|<\|constrain\|>|"' 'r"<\|channel\|>|<\|message\|>|<\|start\|>|<\|return\|>|<\|call\|>|<\|constrain\|>|<turn\|>|"'

    # Also strip <turn|> from content/reasoning in the streaming path after
    # the reasoning parser runs (the parser only strips channel tokens, not
    # the end-of-turn token).
    substituteInPlace vllm_mlx/server.py \
      --replace-fail 'content = delta_msg.content' 'content = SPECIAL_TOKENS_PATTERN.sub("", delta_msg.content) if delta_msg.content else None' \
      --replace-fail 'reasoning = delta_msg.reasoning' 'reasoning = SPECIAL_TOKENS_PATTERN.sub("", delta_msg.reasoning) if delta_msg.reasoning else None'
  '';

  # Darwin-only: MLX is Apple Silicon only
  meta = with lib; {
    description = "vLLM-like inference server for Apple Silicon with MLX";
    homepage = "https://github.com/waybarrios/vllm-mlx";
    license = licenses.asl20;
    platforms = platforms.darwin;
    mainProgram = "vllm-mlx";
  };
}
