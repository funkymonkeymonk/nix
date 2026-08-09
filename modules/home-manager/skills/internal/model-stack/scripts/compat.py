#!/usr/bin/env python3
"""Compatibility calculations for LLM models."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any


# Rough bytes per parameter for common quantization formats
# These are empirical averages; actual sizes vary by model architecture
QUANT_SIZES = {
    "Q2_K": 0.29,
    "Q3_K_S": 0.33,
    "Q3_K_M": 0.37,
    "Q3_K_L": 0.41,
    "Q4_K_S": 0.44,
    "Q4_K_M": 0.50,
    "Q4_0": 0.50,
    "Q5_K_S": 0.55,
    "Q5_K_M": 0.61,
    "Q5_0": 0.61,
    "Q6_K": 0.71,
    "Q8_0": 0.95,
    "F16": 2.0,
    "FP16": 2.0,
    "BF16": 2.0,
    "F32": 4.0,
    "FP32": 4.0,
}

# Quality score (higher = better) - rough mapping
QUANT_QUALITY = {
    "Q2_K": 40,
    "Q3_K_S": 50,
    "Q3_K_M": 55,
    "Q3_K_L": 60,
    "Q4_K_S": 65,
    "Q4_K_M": 72,
    "Q4_0": 70,
    "Q5_K_S": 75,
    "Q5_K_M": 82,
    "Q5_0": 80,
    "Q6_K": 88,
    "Q8_0": 95,
    "F16": 98,
    "FP16": 98,
    "BF16": 98,
    "F32": 100,
    "FP32": 100,
}

# Default to use when no quantization specified
DEFAULT_QUANT = "Q4_K_M"


def parse_param_count(tags: list[str], model_id: str) -> float | None:
    """Extract parameter count in billions from tags or model ID."""
    # Check tags first
    for tag in tags:
        tag_lower = tag.lower()
        # Match patterns like "7b", "13B", "70b", "8x7b", "1.5b"
        match = __import__("re").match(r"^(\d+(?:\.\d+)?)b$", tag_lower)
        if match:
            return float(match.group(1))
        match = __import__("re").match(r"^(\d+)x(\d+(?:\.\d+)?)b$", tag_lower)
        if match:
            # MoE like 8x7b
            return float(match.group(1)) * float(match.group(2))

    # Check model ID
    id_lower = model_id.lower()
    patterns = [
        r"-(\d+(?:\.\d+)?)b-",
        r"-(\d+(?:\.\d+)?)b$",
        r"_(\d+(?:\.\d+)?)b_",
        r"_(\d+(?:\.\d+)?)b$",
    ]
    for pat in patterns:
        match = __import__("re").search(pat, id_lower)
        if match:
            return float(match.group(1))

    return None


# Pre-quantized format memory multipliers (already compressed)
PRE_QUANT_MULTIPLIERS = {
    "awq": 0.55,
    "gptq": 0.55,
    "gguf": 0.50,
    "exl2": 0.45,
    "bnb": 0.50,
}


def detect_prequantized(tags: list[str]) -> str | None:
    """Detect if a model is already quantized (AWQ, GPTQ, etc.)."""
    tag_set = {t.lower() for t in tags}
    for fmt in PRE_QUANT_MULTIPLIERS:
        if fmt in tag_set:
            return fmt
    return None


def estimate_memory_for_model(params_b: float | None, tags: list[str]) -> float | None:
    """Estimate memory usage considering pre-quantized formats."""
    if params_b is None:
        return None

    prequant = detect_prequantized(tags)
    if prequant:
        multiplier = PRE_QUANT_MULTIPLIERS[prequant]
        return params_b * multiplier * 1.2

    # Default to Q4_K_M for unquantized model recommendations
    return estimate_memory_gb(params_b, DEFAULT_QUANT)


def estimate_memory_gb(params_b: float, quant: str = DEFAULT_QUANT) -> float:
    """Estimate memory usage in GB for a model at a given quantization."""
    multiplier = QUANT_SIZES.get(quant.upper(), QUANT_SIZES[DEFAULT_QUANT])
    # Add overhead for KV cache, context, etc. (~20%)
    return params_b * multiplier * 1.2


def get_best_quantization(
    params_b: float,
    vram_gb: float,
    ram_gb: float,
    gpu_backend: str | None = None,
    max_utilization: float = 0.5,
    ceiling: str = "Q8_0",
) -> tuple[str, float] | None:
    """Find the best quantization that fits available memory.

    Args:
        max_utilization: Prefer using no more than this fraction of available
            memory for the base weights. This leaves headroom for KV cache,
            context, and system use. Set to 1.0 to use all available memory.
        ceiling: Maximum quantization quality to recommend. F16/F32 are rarely
            needed for inference and waste memory. Default is Q8_0.
    """
    # If we have a GPU, prefer VRAM. Otherwise use RAM.
    available = vram_gb if vram_gb > 0 else ram_gb
    if available <= 0:
        return None

    ceiling_quality = QUANT_QUALITY.get(ceiling, 100)

    # Sort by quality descending
    quants = sorted(QUANT_SIZES.keys(), key=lambda q: QUANT_QUALITY.get(q, 0), reverse=True)

    best = None
    for quant in quants:
        quality = QUANT_QUALITY.get(quant, 0)
        if quality > ceiling_quality:
            continue
        mem = estimate_memory_gb(params_b, quant)
        if mem <= available:
            if best is None:
                best = (quant, mem)
            # Prefer this quant if it uses less than max_utilization
            if mem <= available * max_utilization:
                return quant, mem

    return best


def score_model(
    params_b: float,
    quant: str,
    mem_gb: float,
    vram_gb: float,
    ram_gb: float,
    gpu_backend: str | None,
    downloads: int = 0,
    likes: int = 0,
) -> dict[str, Any]:
    """Score a model configuration. Returns score breakdown."""
    available = vram_gb if vram_gb > 0 else ram_gb

    # Fit score: how well it uses available memory (0-100)
    if available > 0:
        utilization = mem_gb / available
        if utilization > 1.0:
            fit = 0  # Won't fit
        elif utilization < 0.3:
            fit = 60  # Wastes a lot of memory
        elif utilization < 0.6:
            fit = 85
        elif utilization < 0.85:
            fit = 100
        else:
            fit = 90  # Cutting it close
    else:
        fit = 50

    # Quality score from quantization
    quality = QUANT_QUALITY.get(quant.upper(), 50)

    # Speed score: GPU is much faster
    speed = 20 if not gpu_backend else (100 if gpu_backend in ("cuda", "mps") else 70)

    # Popularity score (log scale)
    pop = min(100, 20 + (downloads / 100000) * 10 + (likes / 1000) * 5)

    # Weighted composite
    composite = int(
        fit * 0.30 + quality * 0.30 + speed * 0.20 + pop * 0.20
    )

    return {
        "fit": int(fit),
        "quality": int(quality),
        "speed": int(speed),
        "popularity": int(pop),
        "composite": composite,
        "fits": fit > 0,
        "estimated_memory_gb": round(mem_gb, 2),
        "quantization": quant,
    }


def format_size(gb: float) -> str:
    """Format gigabytes nicely."""
    if gb >= 1000:
        return f"{gb / 1024:.1f} TB"
    return f"{gb:.1f} GB"


def main() -> None:
    """CLI for testing compatibility calculations."""
    import sys
    if len(sys.argv) < 3:
        print("Usage: compat.py <params_b> <vram_gb> [ram_gb]")
        print("Example: compat.py 7 8 16")
        sys.exit(1)

    params = float(sys.argv[1])
    vram = float(sys.argv[2])
    ram = float(sys.argv[3]) if len(sys.argv) > 3 else 0.0

    result = get_best_quantization(params, vram, ram)
    if result:
        quant, mem = result
        print(f"Best quant for {params}B model with {vram}GB VRAM: {quant} ({mem:.1f} GB)")
        score = score_model(params, quant, mem, vram, ram, "cuda" if vram > 0 else None)
        print(f"Score: {score['composite']} (fit={score['fit']}, quality={score['quality']}, speed={score['speed']})")
    else:
        print("Model does not fit in available memory.")


if __name__ == "__main__":
    main()
