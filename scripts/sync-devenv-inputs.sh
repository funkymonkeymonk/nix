#!/usr/bin/env bash
set -euo pipefail

flake_lock=${1:-flake.lock}
devenv_yaml=${2:-devenv.yaml}

if [ ! -f "$flake_lock" ]; then
  echo "ERROR: flake lock not found: $flake_lock" >&2
  exit 1
fi

if [ ! -f "$devenv_yaml" ]; then
  echo "ERROR: devenv config not found: $devenv_yaml" >&2
  exit 1
fi

python3 - "$flake_lock" "$devenv_yaml" <<'PY'
import json
import re
import sys
from pathlib import Path

lock_path = Path(sys.argv[1])
yaml_path = Path(sys.argv[2])
lock = json.loads(lock_path.read_text())
nodes = lock["nodes"]
root_inputs = nodes["root"]["inputs"]
lines = yaml_path.read_text().splitlines(keepends=True)

in_inputs = False
current_input = None
updated = 0

for index, line in enumerate(lines):
    stripped = line.lstrip()
    indent = len(line) - len(stripped)

    if indent == 0:
        in_inputs = stripped.strip() == "inputs:"
        current_input = None
        continue

    if not in_inputs:
        continue

    if indent == 2 and stripped.rstrip().endswith(":"):
        current_input = stripped.rstrip()[:-1]
        continue

    if indent != 4 or current_input not in root_inputs or not stripped.startswith("url:"):
        continue

    # Keep the project runner on its explicit stable release tag.
    if current_input == "devenv":
        continue

    node_ref = root_inputs[current_input]
    if not isinstance(node_ref, str) or node_ref not in nodes:
        continue

    node = nodes[node_ref]
    revision = node.get("locked", {}).get("rev")
    original = node.get("original", {})
    owner = original.get("owner")
    repo = original.get("repo")
    if not revision or not owner or not repo:
        continue

    url_match = re.fullmatch(r"(\s*url:\s*)([^\s]+)(\s*(?:#.*)?)", line.rstrip("\n"))
    if not url_match:
        raise SystemExit(f"ERROR: cannot parse {current_input} URL in {yaml_path}")

    prefix, old_url, suffix = url_match.groups()
    github_match = re.fullmatch(r"github:([^/]+)/([^/]+)(?:/[^?]*)?(\?.*)?", old_url)
    if not github_match:
        continue

    old_owner, old_repo, query = github_match.groups()
    selected_owner = old_owner if old_owner.lower() == owner.lower() else owner
    selected_repo = old_repo if old_repo.lower() == repo.lower() else repo
    new_url = f"github:{selected_owner}/{selected_repo}/{revision}{query or ''}"
    lines[index] = f"{prefix}{new_url}{suffix}\n"
    updated += old_url != new_url

if updated:
    yaml_path.write_text("".join(lines))

print(f"Synchronized {updated} devenv input URL(s) from {lock_path}")
PY
