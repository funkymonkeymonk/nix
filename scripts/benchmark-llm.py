#!/usr/bin/env python3
"""
Benchmark local LLM server performance.

Tests:
  - Time to first token (TTFT) per model
  - Tokens/second sustained throughput
  - Comfortable concurrent connection limit
  - End-to-end latency distribution

Usage:
  python3 benchmark-llm.py [--host HOST] [--port PORT] [--models MODEL1,MODEL2]

Requires: Python 3.10+ (stdlib only)
"""

import argparse
import json
import statistics
import sys
import time
import urllib.request
from concurrent.futures import ThreadPoolExecutor, as_completed
from dataclasses import dataclass, field
from typing import Optional


@dataclass
class BenchmarkResult:
    model: str
    ttft_ms: float = 0.0          # Time to first token in milliseconds
    total_tokens: int = 0
    tokens_per_sec: float = 0.0
    total_time_ms: float = 0.0
    success: bool = False
    error: Optional[str] = None


@dataclass
class ModelReport:
    model: str
    ttft_tests: list[float] = field(default_factory=list)
    throughput_tests: list[float] = field(default_factory=list)
    concurrency_tests: list = field(default_factory=list)


def make_request(host: str, port: int, model: str, prompt: str, max_tokens: int, stream: bool = True, timeout: int = 120) -> dict:
    """Make a chat completion request and return timing + token data."""
    url = f"http://{host}:{port}/v1/chat/completions"
    payload = {
        "model": model,
        "messages": [{"role": "user", "content": prompt}],
        "max_tokens": max_tokens,
        "temperature": 0.1,
        "stream": stream,
    }
    data = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(
        url, data=data, headers={"Content-Type": "application/json"}, method="POST"
    )

    start_time = time.time()
    first_token_time: Optional[float] = None
    token_count = 0
    full_text = ""

    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            for raw_line in resp:
                line = raw_line.decode("utf-8").strip()
                if line.startswith("data: "):
                    chunk = line[6:]
                    if chunk == "[DONE]":
                        break
                    try:
                        parsed = json.loads(chunk)
                        delta = parsed.get("choices", [{}])[0].get("delta", {})
                        content = delta.get("content", "") or ""
                        reasoning = delta.get("reasoning_content", "") or ""
                        text = content + reasoning
                        if text:
                            if first_token_time is None:
                                first_token_time = time.time()
                            token_count += 1
                            full_text += text
                    except json.JSONDecodeError:
                        pass

        total_time = time.time() - start_time
        ttft = (first_token_time - start_time) * 1000 if first_token_time else 0.0

        return {
            "success": True,
            "ttft_ms": ttft,
            "total_tokens": token_count,
            "total_time_ms": total_time * 1000,
            "tokens_per_sec": token_count / total_time if total_time > 0 else 0.0,
            "text": full_text,
        }
    except Exception as e:
        return {"success": False, "error": str(e), "total_time_ms": (time.time() - start_time) * 1000}


def test_ttft(host: str, port: int, model: str, runs: int = 3) -> list[float]:
    """Test time-to-first-token multiple times."""
    print(f"  [{model}] Testing TTFT ({runs} runs)...")
    results = []
    for i in range(runs):
        result = make_request(host, port, model, "Explain quantum computing in one sentence.", max_tokens=5)
        if result["success"]:
            print(f"    Run {i+1}: TTFT={result['ttft_ms']:.0f}ms")
            results.append(result["ttft_ms"])
        else:
            print(f"    Run {i+1}: FAILED - {result['error']}")
    return results


def test_throughput(host: str, port: int, model: str, max_tokens: int = 256) -> Optional[float]:
    """Test sustained token generation speed."""
    print(f"  [{model}] Testing throughput (max_tokens={max_tokens})...")
    result = make_request(
        host, port, model,
        "Write a short paragraph about artificial intelligence.",
        max_tokens=max_tokens,
    )
    if result["success"]:
        tps = result["tokens_per_sec"]
        print(f"    Generated {result['total_tokens']} tokens in {result['total_time_ms']:.0f}ms = {tps:.1f} tok/s")
        return tps
    else:
        print(f"    FAILED - {result['error']}")
        return None


def test_concurrency(host: str, port: int, model: str, concurrency: int, max_tokens: int = 50) -> dict:
    """Test how the model handles N concurrent requests."""
    print(f"  [{model}] Testing concurrency={concurrency}...")

    def _worker(_idx: int) -> dict:
        return make_request(
            host, port, model,
            f"Concurent request #{_idx}. Say hello.",
            max_tokens=max_tokens,
            timeout=180,
        )

    start = time.time()
    results = []
    with ThreadPoolExecutor(max_workers=concurrency) as pool:
        futures = [pool.submit(_worker, i) for i in range(concurrency)]
        for fut in as_completed(futures):
            results.append(fut.result())
    total_elapsed = time.time() - start

    successes = [r for r in results if r["success"]]
    failures = [r for r in results if not r["success"]]

    ttfts = [r["ttft_ms"] for r in successes if r.get("ttft_ms")]
    tokens = sum(r.get("total_tokens", 0) for r in successes)

    report = {
        "concurrency": concurrency,
        "total_requests": len(results),
        "success": len(successes),
        "failed": len(failures),
        "total_time_s": total_elapsed,
        "tokens_generated": tokens,
        "avg_tps": tokens / total_elapsed if total_elapsed > 0 else 0,
    }

    if ttfts:
        report["avg_ttft_ms"] = statistics.mean(ttfts)
        report["max_ttft_ms"] = max(ttfts)
        report["min_ttft_ms"] = min(ttfts)
        report["p95_ttft_ms"] = statistics.quantiles(ttfts, n=20)[18] if len(ttfts) >= 20 else max(ttfts)

    if failures:
        report["errors"] = [r["error"] for r in failures][:3]

    print(f"    Success: {len(successes)}/{len(results)} | Avg TTFT: {report.get('avg_ttft_ms', 0):.0f}ms | Throughput: {report['avg_tps']:.1f} tok/s")
    if failures:
        print(f"    Errors: {len(failures)} (sample: {failures[0]['error'][:80]})")

    return report


def find_max_concurrency(host: str, port: int, model: str, max_tokens: int = 50, max_concurrency: int = 16) -> int:
    """Find the max comfortable concurrency by binary search / stepping."""
    print(f"  [{model}] Finding comfortable concurrency limit...")
    comfortable = 1
    for level in [1, 2, 4, 8, 16]:
        if level > max_concurrency:
            break
        report = test_concurrency(host, port, model, level, max_tokens)
        if report["failed"] == 0 and report.get("avg_ttft_ms", 99999) < 60000:
            comfortable = level
        else:
            break
    print(f"    Comfortable concurrency: {comfortable}")
    return comfortable


def health_check(host: str, port: int) -> bool:
    try:
        req = urllib.request.Request(f"http://{host}:{port}/health", method="GET")
        with urllib.request.urlopen(req, timeout=5) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            return data.get("status") == "healthy"
    except Exception:
        return False


def discover_models(host: str, port: int) -> list[str]:
    try:
        req = urllib.request.Request(f"http://{host}:{port}/v1/models", method="GET")
        with urllib.request.urlopen(req, timeout=5) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            return [m["id"] for m in data.get("data", [])]
    except Exception as e:
        print(f"Could not discover models: {e}")
        return []


def main() -> int:
    parser = argparse.ArgumentParser(description="Benchmark local LLM server")
    parser.add_argument("--host", default="localhost", help="Server host")
    parser.add_argument("--port", type=int, default=8300, help="Server port")
    parser.add_argument("--models", default="", help="Comma-separated model IDs (auto-detected if empty)")
    parser.add_argument("--max-concurrency", type=int, default=16, help="Max concurrency to test")
    parser.add_argument("--output", default="", help="Write JSON report to file")
    parser.add_argument("--quick", action="store_true", help="Quick mode: fewer runs")
    args = parser.parse_args()

    print("=" * 60)
    print("LLM Server Benchmark")
    print("=" * 60)
    print(f"Target: http://{args.host}:{args.port}")

    if not health_check(args.host, args.port):
        print("ERROR: Server is not healthy or not responding.")
        return 1

    models = [m.strip() for m in args.models.split(",") if m.strip()] if args.models else discover_models(args.host, args.port)
    if not models:
        print("ERROR: No models found or specified.")
        return 1

    print(f"Models: {', '.join(models)}")
    print()

    report = {
        "server": f"http://{args.host}:{args.port}",
        "models": {},
    }

    for model in models:
        print(f"\n{'=' * 60}")
        print(f"Model: {model}")
        print(f"{'=' * 60}")

        model_report = {}

        # 1. TTFT test
        ttft_runs = 1 if args.quick else 3
        ttfts = test_ttft(args.host, args.port, model, runs=ttft_runs)
        if ttfts:
            model_report["ttft_ms"] = {
                "values": ttfts,
                "median": statistics.median(ttfts),
                "mean": statistics.mean(ttfts),
                "min": min(ttfts),
                "max": max(ttfts),
            }
            if model_report["ttft_ms"]["median"] > 60000:
                print(f"  WARNING: TTFT exceeds 60s threshold!")

        # 2. Throughput test
        tps = test_throughput(args.host, args.port, model, max_tokens=128 if args.quick else 256)
        if tps is not None:
            model_report["throughput_tok_per_sec"] = tps

        # Quick streaming sanity check for TTFT with actual tokens
        print(f"  [{model}] Streaming sanity check...")
        result = make_request(
            args.host, args.port, model,
            "Say hello in exactly 5 words.", max_tokens=10, stream=True
        )
        if result["success"] and result["total_tokens"] > 0:
            print(f"    Stream OK: {result['total_tokens']} tokens, TTFT={result['ttft_ms']:.0f}ms")
        else:
            print(f"    Stream issue: tokens={result.get('total_tokens', 0)}, err={result.get('error', 'N/A')}")

        # 3. Concurrency limit
        comfy = find_max_concurrency(args.host, args.port, model, max_concurrency=args.max_concurrency)
        model_report["comfortable_concurrency"] = comfy

        # 4. Detailed concurrency at comfortable level
        if comfy > 1:
            conc_report = test_concurrency(args.host, args.port, model, comfy, max_tokens=50)
            model_report["concurrency_at_comfortable"] = conc_report

        report["models"][model] = model_report

    # Summary
    print(f"\n{'=' * 60}")
    print("SUMMARY")
    print(f"{'=' * 60}")
    for model, data in report["models"].items():
        ttft = data.get("ttft_ms", {})
        tps = data.get("throughput_tok_per_sec", 0.0)
        comfy = data.get("comfortable_concurrency", 0)
        status = "PASS" if ttft.get("median", 99999) < 60000 else "FAIL (>60s)"
        print(f"  {model}:")
        print(f"    TTFT: {ttft.get('median', 'N/A'):.0f}ms median {status}")
        print(f"    Throughput: {tps:.1f} tok/s")
        print(f"    Comfortable concurrency: {comfy}")

    if args.output:
        with open(args.output, "w") as f:
            json.dump(report, f, indent=2)
        print(f"\nReport written to: {args.output}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
