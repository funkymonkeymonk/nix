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
  version = "0.4.0";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "waybarrios";
    repo = "vllm-mlx";
    tag = "v${version}";
    hash = "sha256-YVon+ta/hf1bnew2q4BhLSnO9XJYalY+Qf/IlBurvyQ=";
  };

  nativeBuildInputs = with python3Packages; [
    setuptools
    wheel
    pythonRelaxDepsHook
  ];

  # Emit a terminal finish_reason chunk when the engine's finished output is
  # swallowed by a parser `continue` in stream_chat_completion (e.g. a bare
  # <turn|> end-of-turn token after a completed tool call). Without it the
  # stream ends tool_calls(finish_reason=null) -> [DONE] and OpenAI clients
  # (pi) abort with "Stream ended without finish_reason". Not fixed upstream
  # as of v0.4.0.
  #
  # Allow system-prompt KV cache snapshots when the model mixes plain KVCache
  # and RotatingKVCache (e.g. Gemma 4). The upstream 0.4.0 probe disables
  # snapshots for any non-KVCache class, forcing a full re-prefill on every
  # turn. mlx-lm exposes the extra cursor metadata via meta_state, so capture
  # and restore it alongside the array state. Not fixed upstream as of v0.4.0.
  patches = [
    # fix(server): emit terminal finish_reason chunk when parsers swallow the
    # finished output.  A finished=True engine output consumed by a parser
    # `continue` (e.g. gemma4 emits the complete tool call in one delta, then
    # a bare <turn|> end-of-turn token as the terminal delta) ends the stream
    # with the tool_calls chunk (finish_reason=null) followed by [DONE] and no
    # finish_reason chunk.  Strict OpenAI clients abort with "Stream ended
    # without finish_reason".  Track whether any emitted chunk carried a
    # non-null finish_reason; after the streaming loop, if the engine's
    # finished output was suppressed, emit the terminal chunk.  Refs #672.
    ./emit-terminal-finish-chunk.patch

    # Allow system-prompt KV cache snapshots when the model mixes plain KVCache
    # and RotatingKVCache (e.g. Gemma 4). The upstream 0.4.0 probe disables
    # snapshots for any non-KVCache class, forcing a full re-prefill on every
    # turn. mlx-lm exposes the extra cursor metadata via meta_state, so capture
    # and restore it alongside the array state. Not fixed upstream as of v0.4.0.
    ./snapshot-rotating-kv-cache.patch

    # fix(simple-engine): preserve streaming finish reasons.  Natural generator
    # exhaustion currently emits a final chunk with no finish reason.  Strict
    # OpenAI clients treat that as a truncated stream.  This stamps natural
    # exhaustion as `stop`, and fixes the engine-enforced token-limit fallback
    # so a backend chunk with no reason is reported as `length`, while
    # preserving explicit backend reasons.  Refs #628.
    #
    # This is the engine half of the #672 fix; the server half above handles
    # finish_reasons that are swallowed by parser `continue`.  Both patches
    # are needed for a complete fix.
    ./fix-engine-finish-reason.patch
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
