#!/usr/bin/env python3
"""Download a model using the best available hosting stack."""

from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
from typing import Any

_SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
if _SCRIPT_DIR not in sys.path:
    sys.path.insert(0, _SCRIPT_DIR)


def load_hw_info() -> dict[str, Any] | None:
    """Load hardware and stack info."""
    cache_path = os.path.join(_SCRIPT_DIR, ".hw_cache.json")
    if os.path.exists(cache_path):
        with open(cache_path) as f:
            return json.load(f)

    try:
        result = subprocess.run(
            [sys.executable, os.path.join(_SCRIPT_DIR, "detect.py")],
            capture_output=True, text=True, timeout=30
        )
        lines = result.stdout.split("\n")
        json_start = None
        for i, line in enumerate(lines):
            if line.strip() == "--- JSON ---":
                json_start = i + 1
                break
        if json_start is not None:
            data = json.loads("\n".join(lines[json_start:]))
            with open(cache_path, "w") as f:
                json.dump(data, f)
            return data
    except Exception:
        pass
    return None


def has_stack(stacks: list[dict], name: str) -> bool:
    return any(s["name"] == name for s in stacks)


def ollama_pull(model: str) -> bool:
    """Download via Ollama."""
    ollama = shutil.which("ollama")
    if not ollama:
        return False

    print(f"🦙 Downloading '{model}' via Ollama...")
    try:
        result = subprocess.run(
            [ollama, "pull", model],
            check=False,
        )
        return result.returncode == 0
    except Exception as e:
        print(f"Error: {e}")
        return False


def hf_download(repo_id: str, local_dir: str | None = None) -> bool:
    """Download via huggingface-cli."""
    hf_cli = shutil.which("huggingface-cli")
    if not hf_cli:
        # Try to use Python API
        try:
            from huggingface_hub import snapshot_download
            print(f"🤗 Downloading '{repo_id}' via huggingface_hub...")
            path = snapshot_download(repo_id, local_dir=local_dir)
            print(f"Downloaded to: {path}")
            return True
        except ImportError:
            print("huggingface_hub not installed. Run: python3 -m pip install huggingface_hub")
            return False
        except Exception as e:
            print(f"Error: {e}")
            return False

    cmd = [hf_cli, "download", repo_id]
    if local_dir:
        cmd.extend(["--local-dir", local_dir])
    print(f"🤗 Downloading '{repo_id}' via huggingface-cli...")
    try:
        result = subprocess.run(cmd, check=False)
        return result.returncode == 0
    except Exception as e:
        print(f"Error: {e}")
        return False


def git_lfs_clone(repo_id: str) -> bool:
    """Fallback: clone with git-lfs."""
    git = shutil.which("git")
    if not git:
        return False

    url = f"https://huggingface.co/{repo_id}"
    target = repo_id.replace("/", "--")
    print(f"📦 Cloning '{repo_id}' with git...")
    try:
        result = subprocess.run(
            [git, "clone", url, target],
            check=False,
        )
        return result.returncode == 0
    except Exception as e:
        print(f"Error: {e}")
        return False


def detect_model_format(repo_id: str) -> str:
    """Try to detect if this is an Ollama-style model name or HF repo."""
    # Ollama models are typically simple names like "llama3.2", "qwen2.5-coder"
    # HF repos are "owner/name" with a slash
    if "/" not in repo_id and " " not in repo_id:
        return "ollama"
    return "hf"


def download(model: str, stack_preference: str | None = None, local_dir: str | None = None) -> bool:
    """Download a model using the best available stack."""
    hw = load_hw_info()
    stacks = hw.get("stacks", []) if hw else []

    fmt = detect_model_format(model)

    # Determine which stack to use
    if stack_preference:
        chosen = stack_preference
    elif fmt == "ollama" and has_stack(stacks, "ollama"):
        chosen = "ollama"
    elif has_stack(stacks, "ollama"):
        chosen = "ollama"
    elif shutil.which("huggingface-cli") or __import__("importlib.util").find_spec("huggingface_hub"):
        chosen = "hf"
    else:
        chosen = "git"

    print(f"Using stack: {chosen}")
    print()

    if chosen == "ollama":
        return ollama_pull(model)
    elif chosen == "hf":
        return hf_download(model, local_dir)
    elif chosen == "git":
        return git_lfs_clone(model)
    else:
        print(f"Unknown stack: {chosen}")
        return False


def main() -> None:
    parser = argparse.ArgumentParser(description="Download a model via the best available stack")
    parser.add_argument("model", help="Model name or Hugging Face repo ID")
    parser.add_argument("--stack", choices=["ollama", "hf", "git"],
                        help="Force a specific download method")
    parser.add_argument("--local-dir", help="Local directory for HF downloads")
    args = parser.parse_args()

    success = download(args.model, args.stack, args.local_dir)
    sys.exit(0 if success else 1)


if __name__ == "__main__":
    main()
