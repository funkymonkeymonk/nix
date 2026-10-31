#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

nix_files() {
  find . -name '*.nix' \
    -not -path './.devenv/*' \
    -not -path './.direnv/*' \
    -not -path './.worktrees/*' \
    -not -path './.workspaces/*' \
    -not -name '.devenv.flake.nix' -print0
}

echo "Checking Nix formatting..."
nix_files | xargs -0 alejandra --check

echo "Checking for dead code..."
nix_files | xargs -0 deadnix --no-underscore --fail

echo "Running static analysis..."
# statix respects .gitignore by default. Existing warnings are non-blocking.
statix check . || true

echo "Checking YAML files..."
find . -type f \( -name '*.yaml' -o -name '*.yml' \) \
  -not -path './.devenv/*' \
  -not -path './.direnv/*' \
  -not -path './.worktrees/*' \
  -not -path './.workspaces/*' \
  -not -path './~/*' \
  -print0 | xargs -0 yamllint --strict

echo "Lint checks complete"
