#!/usr/bin/env python3
"""Search Hugging Face for compatible LLM models."""

from __future__ import annotations

import argparse
import json
import os
import sys
from typing import Any

# Add script dir to path for compat imports
_SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
if _SCRIPT_DIR not in sys.path:
    sys.path.insert(0, _SCRIPT_DIR)

import compat


def load_hw_info() -> dict[str, Any] | None:
    """Load hardware info from detect.py output."""
    # Try to find cached detection output
    cache_path = os.path.join(_SCRIPT_DIR, ".hw_cache.json")
    if os.path.exists(cache_path):
        with open(cache_path) as f:
            return json.load(f)

    # Run detect.py and parse JSON output
    import subprocess
    try:
        result = subprocess.run(
            [sys.executable, os.path.join(_SCRIPT_DIR, "detect.py")],
            capture_output=True, text=True, timeout=30
        )
        # Find JSON section
        lines = result.stdout.split("\n")
        json_start = None
        for i, line in enumerate(lines):
            if line.strip() == "--- JSON ---":
                json_start = i + 1
                break
        if json_start is not None:
            data = json.loads("\n".join(lines[json_start:]))
            # Cache it
            with open(cache_path, "w") as f:
                json.dump(data, f)
            return data
    except Exception:
        pass
    return None


def search_hub(query: str, limit: int = 20, sort: str = "downloads") -> list[dict[str, Any]]:
    """Search Hugging Face Hub for models."""
    try:
        from huggingface_hub import HfApi
    except ImportError:
        print("Error: huggingface_hub is not installed.")
        print("Run: python3 -m pip install huggingface_hub")
        sys.exit(1)

    api = HfApi()

    # Search for GGUF models and regular models
    results = []
    seen = set()

    # First try GGUF-specific search
    try:
        for model in api.list_models(
            search=f"{query} gguf",
            sort=sort,
            limit=limit * 2,
        ):
            if model.id not in seen:
                seen.add(model.id)
                results.append({
                    "id": model.id,
                    "tags": list(getattr(model, "tags", []) or []),
                    "downloads": getattr(model, "downloads", 0) or 0,
                    "likes": getattr(model, "likes", 0) or 0,
                    "pipeline_tag": getattr(model, "pipeline_tag", ""),
                    "library_name": getattr(model, "library_name", ""),
                })
    except Exception as e:
        print(f"Warning: GGUF search failed: {e}")

    # Also search without GGUF tag
    try:
        for model in api.list_models(
            search=query,
            sort=sort,
            limit=limit * 2,
        ):
            if model.id not in seen and len(seen) < limit * 2:
                seen.add(model.id)
                results.append({
                    "id": model.id,
                    "tags": list(getattr(model, "tags", []) or []),
                    "downloads": getattr(model, "downloads", 0) or 0,
                    "likes": getattr(model, "likes", 0) or 0,
                    "pipeline_tag": getattr(model, "pipeline_tag", ""),
                    "library_name": getattr(model, "library_name", ""),
                })
    except Exception as e:
        print(f"Warning: general search failed: {e}")

    return results[:limit]


def get_model_info(model_id: str) -> dict[str, Any] | None:
    """Get detailed info for a specific model."""
    try:
        from huggingface_hub import HfApi
    except ImportError:
        return None

    api = HfApi()
    try:
        info = api.model_info(model_id)
        return {
            "id": info.id,
            "tags": list(getattr(info, "tags", []) or []),
            "downloads": getattr(info, "downloads", 0) or 0,
            "likes": getattr(info, "likes", 0) or 0,
            "pipeline_tag": getattr(info, "pipeline_tag", ""),
            "library_name": getattr(info, "library_name", ""),
            "siblings": [s.rfilename for s in getattr(info, "siblings", []) or []],
        }
    except Exception:
        return None


def analyze_model(model: dict[str, Any], hw: dict[str, Any] | None) -> dict[str, Any]:
    """Analyze a model's compatibility with the current hardware."""
    tags = model.get("tags", [])
    params = compat.parse_param_count(tags, model["id"])

    if not hw:
        return {
            **model,
            "params_b": params,
            "compatibility": None,
        }

    hardware = hw.get("hardware", {})
    gpus = hardware.get("gpus", []) or []
    vram = max((g.get("vram_gb", 0) for g in gpus), default=0.0)
    ram = hardware.get("ram_gb", 0.0)
    backend = gpus[0].get("backend") if gpus else None

    if params:
        prequant = compat.detect_prequantized(tags)
        if prequant:
            # Already quantized model (AWQ, GPTQ, GGUF)
            mem = compat.estimate_memory_for_model(params, tags)
            quant_label = prequant.upper()
            quality = 70  # Pre-quantized quality estimate
            fits = mem is not None and mem <= max(vram, ram)
            score = {
                "fits": fits,
                "composite": 75 if fits else 0,
                "estimated_memory_gb": round(mem, 2) if mem else None,
                "quantization": quant_label,
                "fit": 90 if fits else 0,
                "quality": quality,
                "speed": 100 if backend in ("cuda", "mps") else 70,
                "popularity": min(100, 20 + (model.get("downloads", 0) / 100000) * 10),
            }
        else:
            best = compat.get_best_quantization(params, vram, ram, backend)
            if best:
                quant, mem = best
                score = compat.score_model(
                    params, quant, mem, vram, ram, backend,
                    downloads=model.get("downloads", 0),
                    likes=model.get("likes", 0),
                )
            else:
                score = {
                    "fits": False,
                    "composite": 0,
                    "estimated_memory_gb": round(compat.estimate_memory_gb(params), 2),
                    "quantization": "Q4_K_M",
                }
    else:
        score = None

    return {
        **model,
        "params_b": params,
        "compatibility": score,
    }


def print_results(results: list[dict[str, Any]], hw: dict[str, Any] | None) -> None:
    """Print search results in a readable format."""
    if not results:
        print("No models found.")
        return

    # Show hardware summary
    if hw:
        h = hw.get("hardware", {})
        gpus = h.get("gpus", []) or []
        vram = max((g.get("vram_gb", 0) for g in gpus), default=0.0)
        print(f"📊 Hardware: {h.get('cpu_name', 'Unknown CPU')}, {h.get('ram_gb', 0):.1f}GB RAM", end="")
        if vram > 0:
            print(f", {vram:.1f}GB VRAM ({gpus[0].get('backend', 'gpu')})")
        else:
            print(" (CPU-only)")
        print()

    # Header
    print(f"{'Rank':>4} {'Model':<45} {'Params':>8} {'Mem':>8} {'Score':>5} {'Fits':>5}")
    print("-" * 80)

    # Sort by composite score descending
    scored = [(r, r.get("compatibility", {}) or {}) for r in results]
    scored.sort(key=lambda x: x[1].get("composite", 0) if x[1] else 0, reverse=True)

    for i, (model, comp) in enumerate(scored, 1):
        model_id = model["id"]
        if len(model_id) > 44:
            model_id = model_id[:41] + "..."

        params = model.get("params_b")
        params_str = f"{params:.1f}B" if params else "?"

        if comp:
            mem = comp.get("estimated_memory_gb", 0)
            mem_str = f"{mem:.1f}GB"
            score = comp.get("composite", 0)
            score_str = f"{score}"
            fits = "✅" if comp.get("fits") else "❌"
        else:
            mem_str = "?"
            score_str = "?"
            fits = "?"

        print(f"{i:>4} {model_id:<45} {params_str:>8} {mem_str:>8} {score_str:>5} {fits:>5}")

    print()
    print("Tip: Run with --model <id> for detailed quantization breakdown.")


def print_model_detail(model: dict[str, Any], hw: dict[str, Any] | None) -> None:
    """Print detailed info for a single model."""
    print(f"\n📦 {model['id']}")
    print(f"   Downloads: {model.get('downloads', 0):,}")
    print(f"   Likes: {model.get('likes', 0):,}")
    print(f"   Tags: {', '.join(model.get('tags', [])[:10])}")

    params = model.get("params_b")
    if params:
        print(f"   Estimated params: ~{params:.1f}B")

    if not hw:
        print("   (Run detect.py first for compatibility info)")
        return

    hardware = hw.get("hardware", {})
    gpus = hardware.get("gpus", []) or []
    vram = max((g.get("vram_gb", 0) for g in gpus), default=0.0)
    ram = hardware.get("ram_gb", 0.0)
    backend = gpus[0].get("backend") if gpus else None

    print(f"\n   💻 Hardware: {vram:.1f}GB VRAM, {ram:.1f}GB RAM, backend={backend or 'cpu'}")
    print()

    if not params:
        print("   Cannot estimate compatibility (unknown parameter count).")
        return

    # Show all quantizations
    print(f"   {'Quant':<10} {'Memory':>10} {'Fits':>6} {'Quality':>8} {'Score':>6}")
    print("   " + "-" * 50)

    quants = sorted(compat.QUANT_SIZES.keys(), key=lambda q: compat.QUANT_QUALITY.get(q, 0), reverse=True)
    for quant in quants:
        mem = compat.estimate_memory_gb(params, quant)
        fits = mem <= max(vram, ram) if max(vram, ram) > 0 else False
        quality = compat.QUANT_QUALITY.get(quant, 0)
        score = compat.score_model(params, quant, mem, vram, ram, backend,
                                   downloads=model.get("downloads", 0),
                                   likes=model.get("likes", 0))
        fit_icon = "✅" if fits else "❌"
        print(f"   {quant:<10} {mem:>9.1f}GB {fit_icon:>5} {quality:>7} {score['composite']:>6}")

    # Best recommendation
    best = compat.get_best_quantization(params, vram, ram, backend)
    if best:
        print(f"\n   ⭐ Recommended: {best[0]} ({best[1]:.1f} GB)")


def main() -> None:
    parser = argparse.ArgumentParser(description="Search Hugging Face for compatible LLMs")
    parser.add_argument("query", nargs="?", help="Search query")
    parser.add_argument("--model", help="Show details for a specific model ID")
    parser.add_argument("--limit", type=int, default=20, help="Max results (default: 20)")
    parser.add_argument("--sort", default="downloads", choices=["downloads", "trending", "likes"],
                        help="Sort order (default: downloads)")
    parser.add_argument("--json", action="store_true", help="Output raw JSON")
    args = parser.parse_args()

    if not args.model and not args.query:
        parser.print_help()
        sys.exit(1)

    hw = load_hw_info()

    if args.model:
        info = get_model_info(args.model)
        if not info:
            print(f"Model '{args.model}' not found on Hugging Face.")
            sys.exit(1)
        analyzed = analyze_model(info, hw)
        if args.json:
            print(json.dumps(analyzed, indent=2))
        else:
            print_model_detail(analyzed, hw)
        return

    results = search_hub(args.query, args.limit, args.sort)
    analyzed = [analyze_model(r, hw) for r in results]

    if args.json:
        print(json.dumps(analyzed, indent=2))
    else:
        print_results(analyzed, hw)


if __name__ == "__main__":
    main()
