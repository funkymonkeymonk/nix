#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$REPO_ROOT/.github/scripts/select-pr-checks.sh"

if [[ ! -x "$SCRIPT" ]]; then
  echo "FAIL: executable changed-check selector does not exist: $SCRIPT"
  exit 1
fi

failures=0
assert_selection() {
  local label="$1" expected="$2"
  shift 2
  local actual
  actual="$(printf '%s\n' "$@" | "$SCRIPT")"
  if [[ "$actual" == "$expected" ]]; then
    echo "  PASS: $label selects $expected"
  else
    echo "  FAIL: $label expected $expected, got $actual"
    failures=$((failures + 1))
  fi
}

echo "=== CI Changed Check Selection Tests ==="
assert_selection \
  "Vector implementation" \
  '["nixos-vector-","type-server-log-aggregator","vector-"]' \
  "modules/nixos/vector.nix"
assert_selection \
  "Zero target regression tests" \
  '["drlight-media-storage","phase3-zero","zero-"]' \
  "tests/test-zero.nix"
assert_selection \
  "Headless server regressions include the user wiring check" \
  '["headless-server-users","phase2-cattle"]' \
  "tests/test-phase2-cattle.nix"
assert_selection \
  "Nix unit runner source selects its focused check" \
  '["nix-unit-runner"]' \
  "tests/test-nix-unit-runner.nix"
assert_selection \
  "VM role generator source selects its pure generator test" \
  '["vm-role-generator"]' \
  "tests/test-vm-role-generator.nix"
assert_selection \
  "Documentation-only changes" \
  '[]' \
  "docs/reference/options.md" \
  "README.md"
assert_selection \
  "Shared flake changes select all non-VM checks" \
  '["*"]' \
  "flake.lock" \
  "modules/nixos/vector.nix"
assert_selection \
  "Test registry changes with a focused media test stay scoped" \
  '["drlight-media-","media-center-archetype","type-server-archetypes"]' \
  "tests/default.nix" \
  "tests/test-media-center-archetype.nix"
assert_selection \
  "Standalone test registry changes select all checks" \
  '["*"]' \
  "tests/default.nix"
assert_selection \
  "Secret manifest changes select all non-VM checks" \
  '["*"]' \
  "secretspec.toml"
assert_selection \
  "Unknown configuration files select all non-VM checks" \
  '["*"]' \
  "configs/custom.json"
assert_selection \
  "Markdown documentation changes do not select Nix checks" \
  '[]' \
  "CHANGELOG.md"
assert_selection \
  "Unmapped source changes fail safe to all checks" \
  '["*"]' \
  "modules/nixos/future-module.nix"
assert_selection \
  "Drlight target changes select media and observability checks" \
  '["central-observability","drlight-media-","media-center-archetype","type-server-archetypes"]' \
  "targets/drlight/default.nix"
assert_selection \
  "Workflow changes select all checks" \
  '["*"]' \
  ".github/workflows/pr-validation.yml"

if ((failures > 0)); then
  echo "Results: $failures failure(s)"
  exit 1
fi
echo "Results: all changed-check selector tests passed"
