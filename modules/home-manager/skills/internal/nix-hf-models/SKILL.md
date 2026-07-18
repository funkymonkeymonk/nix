---
name: nix-hf-models
description: >
  Use when pre-downloading HuggingFace models into the Nix store for
  local inference servers (vllm-mlx, ollama, mlx-lm). Covers the hf
  download CLI, fixed-output derivations, hash computation, and
  handling CDN/auth issues that break plain curl.
---

# Pre-Downloading HuggingFace Models in Nix

## The Problem

HuggingFace models are large (multi-GB). Downloading them at runtime:
- Times out and blocks first inference
- Fails on headless machines (no browser for HF auth)
- Wastes bandwidth on every reinstall

Nix can pre-download models as **fixed-output derivations** — downloaded once, cached forever, available instantly at runtime.

## Why curl Fails (And What Works)

| Method | Works? | Why |
|--------|--------|-----|
| `curl` direct | ❌ | HF CDN returns 403 for files >1GB |
| `git lfs` | ❌ | Same CDN auth issue |
| `huggingface-cli` | ❌ | Deprecated, same backend |
| **`hf download`** | ✅ | Uses HF's native Xet CDN protocol |

The `hf` command (from `python3Packages.huggingface-hub`) properly negotiates CDN auth tokens and resumes partial downloads.

## Pattern: fetchModel with hf download

```nix
# packages/mlx-models/default.nix
{
  lib,
  stdenvNoCC,
  python3Packages,
  cacert,
  ...
}: {
  fetchModel = {
    name,
    modelPath,
    outputHash,
    include ? ["*.safetensors" "*.json" "*.jinja"],
    extraHook ? "",
  }:
    stdenvNoCC.mkDerivation {
      pname = name;
      version = "0";
      nativeBuildInputs = [python3Packages.huggingface-hub];
      SSL_CERT_FILE = "${cacert}/etc/ssl/certs/ca-bundle.crt";
      outputHashMode = "recursive";
      outputHashAlgo = "sha256";
      inherit outputHash;
      phases = ["buildPhase" "installPhase"];
      buildPhase = ''
        set -euo pipefail
        echo "Downloading ${modelPath} from HuggingFace..."

        # hf download needs a writable HOME for its cache
        export HOME=$(mktemp -d)

        mkdir -p $out

        ${lib.getExe python3Packages.huggingface-hub} download "${modelPath}" \
          --local-dir "$out" \
          --include "*.safetensors" \
          --include "*.json" \
          --include "*.jinja"

        # Remove HF cache metadata — not deterministic across builds
        rm -rf "$out/.cache"

        echo "Done downloading ${modelPath}."
        ${extraHook}
      '';
      installPhase = "true";
      meta = {
        description = "MLX model: ${modelPath}";
        platforms = lib.platforms.darwin;
      };
    };
}
```

## Register a Model Overlay

```nix
# overlays/default.nix
{inputs ? {}}: final: _prev:
{
  mlx-models = final.callPackage ../packages/mlx-models {};

  gemma4-31B-4bit = final.mlx-models.fetchModel {
    name = "gemma4-31B-4bit";
    modelPath = "mlx-community/gemma-4-31b-it-4bit";
    outputHash = "sha256-CCj8JPBY+WugmwUyk27dUSEwvWnVKNnDPaupsWnrAgk=";
  };
}
```

## Compute the Hash

```bash
# 1. Set outputHash = final.lib.fakeSha256 in the overlay
# 2. Build the model
nix build .#gemma4-31B-4bit --no-link --impure

# 3. Nix fails with the actual hash — copy it into the overlay:
#    got:    sha256-CCj8JPBY+WugmwUyk27dUSEwvWnVKNnDPaupsWnrAgk=

# 4. Rebuild — subsequent builds use the Nix cache
```

## Wire Into the Inference Server

```nix
# modules/services/vllm-mlx/darwin.nix
resolveModelPath = path:
  let
    segments = lib.splitString "/" path;
    modelName = lib.last segments;
    overlayName =
      if modelName == "gemma-4-31b-it-4bit"
      then "gemma4-31B-4bit"
      else null;
  in
    if overlayName != null && pkgs ? ${overlayName}
    then "${pkgs.${overlayName}}"
    else path;
```

This resolves the HF repo ID to a Nix store path when the overlay exists, falling back to the raw ID for runtime download.

## Include Chat Templates

Models need their `.jinja` chat template files or inference fails with:

```
ValueError: tokenizer.chat_template is not set
```

Always include `"*.jinja"` in the `include` pattern:

```nix
${lib.getExe python3Packages.huggingface-hub} download "${modelPath}" \
  --local-dir "$out" \
  --include "*.safetensors" \
  --include "*.json" \
  --include "*.jinja"
```

## Testing a Model Download

```bash
# Quick test: download just metadata to inspect
nix shell nixpkgs#python3Packages.huggingface-hub --command bash -c '
  HF_HOME=/tmp/hf-test hf download mlx-community/gemma-4-31b-it-4bit \
    --local-dir /tmp/model-test \
    --include "config.json" \
    --include "*.jinja"
'

cat /tmp/model-test/config.json | jq .model_type
ls /tmp/model-test/*.jinja
```

## Common Mistakes

| Mistake | Symptom | Fix |
|---------|---------|-----|
| Using `curl` for >1GB files | 403 Forbidden | Use `hf download` instead |
| Missing `.jinja` files | `tokenizer.chat_template is not set` | Add `"*.jinja"` to includes |
| Not removing `.cache/` | Hash mismatch across builds | `rm -rf "$out/.cache"` |
| Using old `huggingface-cli` | Deprecated warning, slow downloads | Use `hf download` |
| Forgetting `export HOME` | `hf` crashes with readonly home | `export HOME=$(mktemp -d)` |
| Wrong `include` pattern | Missing weight files | Use `"*.safetensors"` not `"*.bin"` |

## See Also

- `packages/mlx-models/default.nix` in this repo for the full implementation
- `overlays/default.nix` for model overlay examples
- `modules/services/vllm-mlx/darwin.nix` for runtime resolution logic
