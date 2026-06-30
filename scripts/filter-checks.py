#!/usr/bin/env python3
"""
Filter flake checks based on changed files.

Only returns check names that are relevant to files changed in the current
branch/commit. This avoids building all 56+ check derivations when only a
few files changed, cutting CI time from ~30 min to ~5–10 min.

Usage:
    python3 scripts/filter-checks.py <all_checks.json>

Outputs one check name per line, or the literal string "__ALL__" if the
full suite should be built (conservative fallback).
"""

import json
import subprocess
import sys
from pathlib import Path


# Mapping: (path_prefixes, check_prefixes_or_list)
# If a changed file starts with any path_prefix, the associated checks are included.
# A path_prefix of "__ALL__" means build everything (conservative).
CHECK_MAPPING = [
    # Core / global changes → build everything
    (["flake.nix", "flake.lock", "modules/default.nix"], "__ALL__"),

    # Options affect role tests, config validation, and coverage
    (["modules/common/options.nix"], ["foundation-options", "all-role-tests", "config-validation", "module-coverage"]),

    # Users / onepassword affect config validation and related checks
    (["modules/common/users.nix", "modules/common/onepassword.nix"],
     ["config-validation", "onepassword-guard", "onepassword-config-output"]),

    # Home-manager modules → targeted checks
    (["modules/home-manager/skills/"], ["skills-"]),
    (["modules/home-manager/email"], ["email-"]),
    (["modules/home-manager/sketchybar"], ["sketchybar-"]),
    (["modules/home-manager/opencode"], ["opencode-"]),
    (["modules/home-manager/jj-autosync"], ["jj-autosync-"]),
    (["modules/home-manager/fjj"], ["fjj-"]),
    (["modules/home-manager/aerospace"], ["aerospace-"]),
    (["modules/home-manager/shell"], ["shell-aliases", "zsh-enable-single-location"]),
    (["modules/home-manager/themes"], ["sketchybar-theme"]),
    (["modules/home-manager/vane-secrets"], ["vane-"]),
    (["modules/home-manager/watch-ci-jobs"], ["workspace-switch"]),
    (["modules/home-manager/zellij"], []),  # no dedicated check yet
    (["modules/home-manager/charm"], []),
    (["modules/home-manager/pi-coding-agent"], ["pi-"]),
    (["modules/home-manager/claude-code"], ["claude-code-"]),

    # Services → targeted checks
    (["modules/services/vane/"], ["vane-"]),
    (["modules/services/ollama/"], ["vllm-mlx-options", "megamanx-vllm"]),
    (["modules/services/bifrost/"], ["bifrost-"]),
    (["modules/services/caddy/"], ["caddy-"]),
    (["modules/services/searxng/"], ["searxng-"]),
    (["modules/services/openclaw/"], ["openclaw-", "llm-client-"]),
    (["modules/services/lume/"], ["lume-"]),
    (["modules/services/microvm-host/"], []),

    # Targets → config validation + phase tests
    (["targets/microvms/"], ["microvm-"]),
    (["targets/zero/"], ["zero-", "phase3-zero"]),
    (["targets/darwin-server/"], ["phase4-darwin-server"]),
    (["targets/bootstrap/"], ["phase5-core-bootstrap"]),
    (["targets/core/"], ["phase5-core-bootstrap"]),
    (["targets/wweaver/"], ["config-validation"]),
    (["targets/MegamanX/"], ["config-validation", "megamanx-vllm"]),
    (["targets/type-nas/"], ["config-validation"]),
    (["targets/"], ["config-validation", "phase2-cattle"]),

    # Library / archetypes → phase tests
    (["library/"], ["phase2-cattle", "phase3-zero", "phase4-darwin-server", "phase5-core-bootstrap"]),

    # Overlays / packages → package tests
    (["overlays/", "packages/"], ["core-packages", "foundation-packages"]),

    # NixOS-specific modules
    (["modules/nixos/"], ["config-validation", "typed-attrs-options"]),
    (["machine-types/"], ["config-validation", "phase2-cattle"]),

    # OS-level configs
    (["os/"], ["config-validation"]),

    # Disk configs
    (["disk-configs/"], ["config-validation"]),

    # Tests changed → rebuild everything to validate the tests themselves
    (["tests/"], "__ALL__"),

    # CI / workflow changes → rebuild everything
    ([".github/"], "__ALL__"),

    # Docs don't affect checks (handled by changes job)
    (["docs/", "README.md", "AGENTS.md"], []),
]


def get_changed_files() -> list[str]:
    """Detect changed files using git."""
    # Try origin/main first (CI and most local clones)
    for base in ["origin/main", "main"]:
        try:
            result = subprocess.run(
                ["git", "merge-base", "HEAD", base],
                capture_output=True,
                text=True,
                check=True,
            )
            merge_base = result.stdout.strip()
            result = subprocess.run(
                ["git", "diff", "--name-only", f"{merge_base}..HEAD"],
                capture_output=True,
                text=True,
                check=True,
            )
            files = [f for f in result.stdout.strip().split("\n") if f]
            if files:
                return files
        except (subprocess.CalledProcessError, FileNotFoundError):
            continue

    # Fallback: diff against HEAD^ (single commit)
    try:
        result = subprocess.run(
            ["git", "diff", "--name-only", "HEAD^", "HEAD"],
            capture_output=True,
            text=True,
            check=True,
        )
        files = [f for f in result.stdout.strip().split("\n") if f]
        if files:
            return files
    except (subprocess.CalledProcessError, FileNotFoundError):
        pass

    # No changed files detected
    return []


def filter_checks(all_checks: list[str], changed_files: list[str]) -> list[str] | str:
    """Return relevant checks or '__ALL__' for full suite."""
    if not changed_files:
        return "__ALL__"

    matched_checks: set[str] = set()
    unmatched_files: list[str] = []

    for changed_file in changed_files:
        file_matched = False
        for prefixes, checks in CHECK_MAPPING:
            if any(changed_file.startswith(p) or changed_file == p for p in prefixes):
                file_matched = True
                if checks == "__ALL__":
                    return "__ALL__"
                if checks:
                    for check in checks:
                        if check.endswith("-"):
                            # Prefix match
                            matched_checks.update(c for c in all_checks if c.startswith(check))
                        else:
                            # Exact match or contains
                            matched_checks.update(c for c in all_checks if c == check or check in c)
                break
        if not file_matched:
            unmatched_files.append(changed_file)

    # If any file didn't match a known pattern, be conservative and run everything
    if unmatched_files:
        # Log which files caused the fallback (to stderr)
        print(f"filter-checks: unmatched files caused fallback: {unmatched_files}", file=sys.stderr)
        return "__ALL__"

    # Always include config-validation if any non-test, non-doc file changed
    # (it's the most important gate)
    if "config-validation" in all_checks:
        matched_checks.add("config-validation")

    return sorted(matched_checks)


def main() -> int:
    import argparse

    parser = argparse.ArgumentParser(description="Filter flake checks based on changed files")
    parser.add_argument("all_checks_json", help="JSON file with list of all check names")
    parser.add_argument(
        "--files",
        help="Comma-separated list of changed files (skips git detection)",
        default=None,
    )
    args = parser.parse_args()

    with open(args.all_checks_json) as f:
        all_checks = json.load(f)

    if args.files:
        changed_files = [f.strip() for f in args.files.split(",") if f.strip()]
    elif "CHANGED_FILES" in __import__("os").environ:
        changed_files = [f.strip() for f in __import__("os").environ["CHANGED_FILES"].split("\n") if f.strip()]
    else:
        changed_files = get_changed_files()

    if not changed_files:
        print("filter-checks: no changed files detected, building all checks", file=sys.stderr)
        print("__ALL__")
        return 0

    print(f"filter-checks: changed files: {changed_files}", file=sys.stderr)

    result = filter_checks(all_checks, changed_files)

    if result == "__ALL__":
        print("filter-checks: building all checks", file=sys.stderr)
        print("__ALL__")
    else:
        print(f"filter-checks: selected {len(result)} of {len(all_checks)} checks", file=sys.stderr)
        for check in result:
            print(check)

    return 0


if __name__ == "__main__":
    sys.exit(main())
