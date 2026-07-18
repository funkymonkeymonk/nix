#!/usr/bin/env bash
# Patch a uv-installed vllm-mlx to fix Gemma 4 GPU thread-local stream issues.
#
# The nixpkgs mlx package is built without Metal support (upstream explicitly
# disables it because Metal requires Xcode). A uv-installed vllm-mlx uses a
# locally-built mlx with Metal, but the PyPI vllm-mlx / mlx-lm wheels lack
# patches for cross-thread MLX stream handling that are required for Gemma 4
# models on Apple Silicon.
#
# Usage:
#   scripts/patch-uv-vllm-mlx.sh [UV_ENV_DIR]
#
# Defaults to: ~/.local/share/uv/tools/vllm-mlx

set -euo pipefail

UV_DIR="${1:-$HOME/.local/share/uv/tools/vllm-mlx}"
if [ ! -d "$UV_DIR" ]; then
    echo "ERROR: uv vllm-mlx not found at $UV_DIR"
    exit 1
fi

PY="$UV_DIR/lib/python3.13/site-packages"

echo "Patching uv vllm-mlx at $UV_DIR ..."

# Patch 1: mlx-lm generate.py
GEN="$PY/mlx_lm/generate.py"
if grep -q "_generation_stream_storage" "$GEN" 2>/dev/null; then
    echo "  generate.py already patched, skipping"
else
    python3 -c "
import re
path = '$GEN'
with open(path, 'r') as f:
    text = f.read()

text = text.replace('import time\n', 'import time\nimport threading\n')

old = '''# A stream on the default device just for generation
generation_stream = mx.new_thread_local_stream(mx.default_device())'''
new = '''# Per-thread generation stream. See https://github.com/ml-explore/mlx-lm/issues/1256
_generation_stream_storage = threading.local()

def generation_stream() -> mx.Stream:
    s = getattr(_generation_stream_storage, 'stream', None)
    if s is None:
        s = mx.new_stream(mx.default_device())
        _generation_stream_storage.stream = s
    return s

def set_generation_stream(stream: mx.Stream) -> None:
    _generation_stream_storage.stream = stream'''
text = text.replace(old, new)

text = text.replace('with mx.stream(generation_stream):', 'with mx.stream(generation_stream()):')
text = text.replace('with wired_limit(model, [generation_stream]):', 'with wired_limit(model, [generation_stream()]):')
text = text.replace('self._stream = stream or generation_stream', 'self._stream = stream or generation_stream()')

old_close = '        mx.synchronize(self._stream)\n        mx.set_wired_limit(self._old_wired_limit)'
new_close = '''        try:
            mx.synchronize(self._stream)
        except RuntimeError:
            pass
        mx.set_wired_limit(self._old_wired_limit)'''
text = text.replace(old_close, new_close)

with open(path, 'w') as f:
    f.write(text)
print('  Patched generate.py')
"
fi

# Patch 2: vllm-mlx mlx_streams.py
STREAMS="$PY/vllm_mlx/mlx_streams.py"
if grep -q 'set_generation_stream' "$STREAMS" 2>/dev/null; then
    echo "  mlx_streams.py already patched, skipping"
else
    sed -i '' 's/if hasattr(module, \"generation_stream\"):/if hasattr(module, \"set_generation_stream\"):/g' "$STREAMS"
    sed -i '' 's/setattr(module, \"generation_stream\", default_stream)/module.set_generation_stream(default_stream)/g' "$STREAMS"
    echo "  Patched mlx_streams.py"
fi

# Patch 3: vllm-mlx text_model_from_vlm.py
TFMV="$PY/vllm_mlx/text_model_from_vlm.py"
if grep -q 'Realize every array the model holds' "$TFMV" 2>/dev/null; then
    echo "  text_model_from_vlm.py already patched, skipping"
else
    python3 -c "
path = '$TFMV'
with open(path, 'r') as f:
    text = f.read()

old_block = '''        text_model.train(False)

        return text_model'''

new_block = '''        text_model.train(False)

        # Realize every array the model holds before it leaves the build
        # thread — including underscore-private module attributes such as
        # RoPE._freqs, which parameters() excludes. MLX lazy graphs are tagged
        # to the stream of the thread that recorded them; a lazy array
        # surviving into generation dies with \"There is no Stream(gpu, N) in
        # current thread\" the moment a worker on another thread evaluates it.
        if hasattr(text_model, \"modules\"):
            mx.eval(
                [
                    v
                    for module in text_model.modules()
                    for v in module.values()
                    if isinstance(v, mx.array)
                ]
            )

        return text_model'''

text = text.replace(old_block, new_block)

with open(path, 'w') as f:
    f.write(text)
print('  Patched text_model_from_vlm.py')
"
fi

echo "Done. Restart vllm-mlx for changes to take effect."
