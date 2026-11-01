#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repo_root"

stderr=$(mktemp)
trap 'rm -f "$stderr"' EXIT

if ! nix eval --impure --no-eval-cache --raw \
  '.#darwinConfigurations.MegamanX.config.system.build.toplevel.drvPath' \
  >/dev/null 2>"$stderr"; then
  cat "$stderr" >&2
  echo 'MegamanX platform evaluation failed' >&2
  exit 1
fi

if grep -E "evaluation warning: ('system' has been renamed|stdenv\\.isDarwin is deprecated)" "$stderr"; then
  echo 'MegamanX evaluation still uses deprecated platform attributes' >&2
  exit 1
fi

printf 'MegamanX platform deprecation checks passed\n'
