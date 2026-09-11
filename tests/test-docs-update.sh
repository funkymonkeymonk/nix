#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
temp_root=$(mktemp -d)
trap 'rm -rf "$temp_root"' EXIT

mkdir -p "$temp_root/scripts" "$temp_root/docs"/{tutorials,how-to,reference,explanation} "$temp_root/modules/roles"
cp "$repo_root/scripts/docs-update.sh" "$temp_root/scripts/docs-update.sh"

if (cd "$temp_root" && bash scripts/docs-update.sh --generate-only); then
    printf 'Generation must fail when no role modules are available\n' >&2
    exit 1
fi

if grep -q '^### ' "$temp_root/docs/reference/roles.md"; then
    printf 'Generated roles must come only from modules/roles\n' >&2
    exit 1
fi

if grep -R -nE 'llm-host|llm-server' "$repo_root/scripts/docs-update.sh" "$repo_root/prd.json" "$repo_root/docs"; then
    printf 'Dead LLM role references remain in generator or generated metadata\n' >&2
    exit 1
fi
