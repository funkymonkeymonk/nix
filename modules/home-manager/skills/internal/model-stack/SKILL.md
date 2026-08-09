---
name: model-stack
description: >
  Research and recommend the best local LLM model stack for the current machine.
  Detects hardware (CPU, GPU, RAM, VRAM), discovers installed hosting stacks
  (Ollama, llama.cpp, vLLM, etc.), searches Hugging Face for compatible models,
  and enables easy downloads. Use when the user wants to find, evaluate, or
  download local AI models that will run well on their system.
---

# Model Stack Research Skill

Research the best local LLM models and hosting stack for the current machine.

## Overview

This skill detects the local hardware, checks which model hosting stacks are
installed, queries Hugging Face for models, and recommends compatible downloads
with the right quantization for the available resources.

## Setup

The skill includes a Python virtual environment for its dependencies. Set it up
once:

```bash
cd .pi/skills/model-stack
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt
```

Or if you have `uv`:

```bash
cd .pi/skills/model-stack
uv venv
uv pip install -r requirements.txt
```

## Commands

All commands can be run via the wrapper (`scripts/run`) which automatically
uses the skill's venv, or directly with `.venv/bin/python`.

### Detect Hardware and Stacks

```bash
./scripts/run scripts/detect.py
```

Shows:
- CPU cores, architecture
- System RAM
- GPU(s) with VRAM
- Installed hosting stacks and versions

### Search Hugging Face for Compatible Models

```bash
./scripts/run scripts/search.py "<query>" [--limit N] [--sort downloads|trending|likes]
```

Examples:

```bash
./scripts/run scripts/search.py "qwen2.5 coder" --limit 20
./scripts/run scripts/search.py "llama" --sort downloads
./scripts/run scripts/search.py "small vision" --limit 10
```

The output includes a compatibility score for each model based on detected
hardware and available VRAM/RAM.

### Show Model Details and Compatibility

```bash
./scripts/run scripts/search.py --model "<owner/repo>"
```

Shows detailed info for a specific model including estimated memory usage
for each available quantization and whether it will fit.

### Download a Model via Detected Stack

```bash
./scripts/run scripts/download.py "<model>"
```

Downloads using the best available stack:
1. **Ollama**: `ollama pull <model>` (if Ollama is installed)
2. **Hugging Face CLI**: `huggingface-cli download <repo>` (for GGUF/raw)
3. **Git LFS**: fallback for HF repos

If multiple stacks are available, it prefers the one that matches the model
format (Ollama for Ollama models, HF CLI for GGUF/safetensors).

### Full Workflow

```bash
# 1. See what you have
./scripts/run scripts/detect.py

# 2. Find models that fit
./scripts/run scripts/search.py "llama 3.2" --limit 10

# 3. Check if a specific model fits
./scripts/run scripts/search.py --model "unsloth/Llama-3.2-1B-Instruct-GGUF"

# 4. Download the best match
./scripts/run scripts/download.py "llama3.2"
```

## How Compatibility Works

- **VRAM Check**: For unquantized models, the tool estimates memory at Q4_K_M
  as a baseline and finds the best quantization that fits. It caps
  recommendations at Q8_0 to avoid wasting memory on F16/F32 for inference.
- **RAM Check**: If no GPU is detected, models run on CPU and estimates use
  system RAM instead.
- **Pre-quantized Models**: AWQ, GPTQ, GGUF, and EXL2 models are detected from
  tags and their actual compressed sizes are used instead of estimating a new
  quantization.
- **Score**: Combines fit (will it run?), quality (quantization level), speed
  (GPU tier), and community popularity.

## Notes

- GPU detection works for NVIDIA (nvidia-smi), Apple Silicon (sysctl), AMD
  (rocm-smi), and Intel Arc (experimental).
- If no GPU is detected, recommendations favor smaller, CPU-optimized models.
- Hugging Face search uses the public Hub API; no token is required for
  searching, but downloading gated models may need `HF_TOKEN`.
- Hardware info is cached in `scripts/.hw_cache.json` to avoid re-detecting
  on every search.
