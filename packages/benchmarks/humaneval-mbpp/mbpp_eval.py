#!/usr/bin/env python3
"""Minimal functional-correctness scorer for MBPP.

MBPP (Mostly Basic Python Problems) has no official evaluation harness
upstream -- the google-research/mbpp directory contains only a JSONL
dataset. This script mirrors the spirit of OpenAI's human-eval
`evaluate_functional_correctness` (execute a candidate completion, run the
problem's tests, report pass@1) but for MBPP's `test_list` format: a plain
list of `assert` statements that call the target function directly, rather
than HumanEval's `check(candidate)` convention.

Usage:
    mbpp-eval --samples samples.jsonl [--dataset mbpp.jsonl] [--timeout 5]

samples.jsonl: one JSON object per line, each with:
    {"task_id": <int>, "completion": <str>}

`completion` should be a complete, runnable Python snippet (typically a
function definition) that solves the MBPP problem identified by `task_id`.
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import tempfile


def load_dataset(path: str) -> dict:
    problems = {}
    with open(path) as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            row = json.loads(line)
            problems[row["task_id"]] = row
    return problems


def run_one(completion: str, test_list: list, test_setup_code: str, timeout: float):
    program = "\n".join(
        [
            test_setup_code or "",
            completion,
            "\n".join(test_list),
        ]
    )

    fd, path = tempfile.mkstemp(suffix=".py")
    try:
        with os.fdopen(fd, "w") as fh:
            fh.write(program)
        try:
            result = subprocess.run(
                [sys.executable, path],
                capture_output=True,
                timeout=timeout,
                text=True,
            )
            return result.returncode == 0, result.stderr
        except subprocess.TimeoutExpired:
            return False, "timeout"
    finally:
        os.unlink(path)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--samples", required=True, help="JSONL of {task_id, completion}"
    )
    parser.add_argument(
        "--dataset",
        default=os.environ.get("MBPP_DATASET"),
        help="Path to mbpp.jsonl (defaults to $MBPP_DATASET, set by the Nix wrapper)",
    )
    parser.add_argument(
        "--timeout", type=float, default=5.0, help="Per-sample execution timeout (s)"
    )
    args = parser.parse_args()

    if not args.dataset:
        print(
            "error: --dataset not provided and MBPP_DATASET is unset",
            file=sys.stderr,
        )
        return 2

    problems = load_dataset(args.dataset)

    total = 0
    passed = 0
    with open(args.samples) as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            sample = json.loads(line)
            task_id = sample["task_id"]
            completion = sample["completion"]
            problem = problems.get(task_id)
            if problem is None:
                print(f"warning: unknown task_id {task_id}, skipping", file=sys.stderr)
                continue

            total += 1
            ok, err = run_one(
                completion,
                problem["test_list"],
                problem.get("test_setup_code", ""),
                args.timeout,
            )
            print(f"{task_id}: {'PASS' if ok else 'FAIL'}")
            if ok:
                passed += 1
            elif err:
                print(err.strip(), file=sys.stderr)

    if total == 0:
        print("no samples scored", file=sys.stderr)
        return 1

    print(f"\npass@1: {passed}/{total} = {passed / total:.2%}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
