# Patched mlx-lm 0.31.3 — applies PR #1275 to fix sliding-window model hangs
# in server/worker threads (RotatingKVCache + thread-local MLX streams).
# Upstream issue: https://github.com/ml-explore/mlx-lm/issues/1256
{
  lib,
  python3Packages,
  fetchPypi,
}:
python3Packages.buildPythonPackage rec {
  pname = "mlx-lm";
  version = "0.31.3";
  pyproject = true;

  src = fetchPypi {
    pname = "mlx_lm";
    inherit version;
    hash = "sha256-DPOJfsIucG8mWt4ZKenymCJo/i9Jw+a+iuIygIIYkA8=";
  };

  nativeBuildInputs = with python3Packages; [pythonRelaxDepsHook setuptools];

  build-system = with python3Packages; [setuptools];

  dependencies = with python3Packages; [
    mlx
    transformers
    numpy
    sentencepiece
    protobuf
    pyyaml
    jinja2
    requests
    tqdm
    huggingface-hub
    tokenizers
    safetensors
    pillow
    regex
  ];

  # Patch: per-thread generation_stream to fix "There is no Stream(gpu, N)"
  # crashes/hangs when RotatingKVCache runs on worker threads.
  # Equivalent to upstream PR https://github.com/ml-explore/mlx-lm/pull/1275
  postPatch = ''
    python3 << 'PYEOF'
    import re

    with open("mlx_lm/generate.py", "r") as f:
        text = f.read()

    # 1. Add threading import after "import time"
    text = text.replace("import time\n", "import time\nimport threading\n")

    # 2. Replace module-level generation_stream with per-thread getter
    old = '''# A stream on the default device just for generation
generation_stream = mx.new_thread_local_stream(mx.default_device())'''
    new = '''# Per-thread generation stream. See https://github.com/ml-explore/mlx-lm/issues/1256
_generation_stream_storage = threading.local()

def generation_stream() -> mx.Stream:
    """Get or create a generation stream for the current thread.
    Uses threading.local() so each thread gets its own mx.new_stream() with a
    CommandEncoder registered locally, avoiding "There is no Stream(gpu, N) in
    current thread" errors when generation runs on a non-import thread.
    """
    s = getattr(_generation_stream_storage, "stream", None)
    if s is None:
        s = mx.new_stream(mx.default_device())
        _generation_stream_storage.stream = s
    return s'''
    text = text.replace(old, new)

    # 3. Update all `with mx.stream(generation_stream):` → call the function
    text = text.replace("with mx.stream(generation_stream):", "with mx.stream(generation_stream()):")

    # 4. Update wired_limit stream reference
    text = text.replace("with wired_limit(model, [generation_stream]):", "with wired_limit(model, [generation_stream()]):")

    # 5. BatchGenerator stream reference
    text = text.replace("self._stream = stream or generation_stream", "self._stream = stream or generation_stream()")

    # 6. Guard synchronize in close() against cross-thread RuntimeError
    old_close = "        mx.synchronize(self._stream)\n        mx.set_wired_limit(self._old_wired_limit)"
    new_close = """        try:
            mx.synchronize(self._stream)
        except RuntimeError:
            pass
        mx.set_wired_limit(self._old_wired_limit)"""
    text = text.replace(old_close, new_close)

    with open("mlx_lm/generate.py", "w") as f:
        f.write(text)

    print("Patched mlx_lm/generate.py successfully")
    PYEOF
  '';

  pythonImportsCheck = ["mlx_lm"];

  # Tests require network to download models
  doCheck = false;

  meta = {
    description = "LLMs on Apple Silicon with MLX (patched for thread-local streams)";
    homepage = "https://github.com/ml-explore/mlx-lm";
    license = lib.licenses.mit;
    platforms = lib.platforms.darwin;
  };
}
