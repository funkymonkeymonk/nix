#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SELECTOR="$REPO_ROOT/.github/scripts/select-pr-validation-checks.sh"
WORKFLOW="$REPO_ROOT/.github/workflows/pr-validation.yml"
failures=0

assert_selection() {
  local label="$1" expected="$2"
  shift 2
  local actual
  if [[ "${1:-}" == "--all" ]]; then
    actual="$(bash "$SELECTOR" --all)"
  else
    actual="$(printf '%s\n' "$@" | bash "$SELECTOR")"
  fi
  if [[ "$actual" == "$expected" ]]; then
    printf '  PASS: %s selects %q\n' "$label" "$expected"
  else
    printf '  FAIL: %s expected %q, got %q\n' "$label" "$expected" "$actual"
    failures=$((failures + 1))
  fi
}

assert_contains() {
  local label="$1" content="$2" expected="$3"
  if grep -Fq -- "$expected" <<<"$content"; then
    echo "  PASS: $label"
  else
    echo "  FAIL: $label"
    failures=$((failures + 1))
  fi
}

workflow_step() {
  local step_name="$1"
  awk -v target="      - name: $step_name" '
    $0 == target { active = 1; print; next }
    active && /^      - name:/ { exit }
    active { print }
  ' "$WORKFLOW"
}

echo "=== CI PR Validation Path Selection Tests ==="

if [[ -f "$SELECTOR" ]]; then
  assert_selection "Disk configuration changes" \
    $'disko-files=true\ninstall-machine-script=false' \
    "disk-configs/zero.nix"
  assert_selection "Flake input changes" \
    $'disko-files=true\ninstall-machine-script=false' \
    "flake.nix"
  assert_selection "Flake lock changes" \
    $'disko-files=true\ninstall-machine-script=false' \
    "flake.lock"
  assert_selection "Unrelated documentation changes" \
    $'disko-files=false\ninstall-machine-script=false' \
    "docs/reference/options.md" "README.md"
  assert_selection "Installer script changes" \
    $'disko-files=false\ninstall-machine-script=true' \
    "scripts/install-machine.sh"
  assert_selection "Nearby unrelated scripts" \
    $'disko-files=false\ninstall-machine-script=false' \
    "scripts/install-machine.sh.bak"
  assert_selection "Combined disk and installer changes" \
    $'disko-files=true\ninstall-machine-script=true' \
    "disk-configs/zero.nix" "scripts/install-machine.sh"
  assert_selection "Manual dispatch selects both validations" \
    $'disko-files=true\ninstall-machine-script=true' \
    --all
else
  echo "  FAIL: path-selection helper exists for behavioral tests"
  failures=$((failures + 1))
fi

selection_step="$(workflow_step "Select changed checks and PR validations")"
disko_step="$(workflow_step "Validate Disko configuration")"
installer_step="$(workflow_step "Validate installation script")"

assert_contains "workflow selection step has the expected id" \
  "$selection_step" "id: changed-checks"
assert_contains "workflow reads the pull request's changed paths" \
  "$selection_step" 'git diff --name-only "$BASE_SHA...$HEAD_SHA" > changed-files.txt'
assert_contains "workflow selection step invokes the path selector" \
  "$selection_step" "bash .github/scripts/select-pr-validation-checks.sh"
assert_contains "workflow feeds changed paths to the selector and writes outputs" \
  "$selection_step" '< changed-files.txt >> "$GITHUB_OUTPUT"'
assert_contains "manual dispatch selects both validation paths" \
  "$selection_step" 'bash .github/scripts/select-pr-validation-checks.sh --all'
assert_contains "workflow outputs consume Disko selection from that step" \
  "$(cat "$WORKFLOW")" \
  'disko-files: ${{ steps.changed-checks.outputs.disko-files }}'
assert_contains "workflow outputs consume installer selection from that step" \
  "$(cat "$WORKFLOW")" \
  'install-machine-script: ${{ steps.changed-checks.outputs.install-machine-script }}'
assert_contains "Disko step consumes its matching validation output" \
  "$disko_step" "needs.changes.outputs.disko-files == 'true'"
assert_contains "Disko step builds the configured Disko script" \
  "$disko_step" ".#nixosConfigurations.zero.config.system.build.diskoScript"
assert_contains "installer step consumes its matching validation output" \
  "$installer_step" "needs.changes.outputs.install-machine-script == 'true'"
assert_contains "installer step retains syntax and executable checks" \
  "$installer_step" "bash -n scripts/install-machine.sh && test -x scripts/install-machine.sh"
assert_contains "Disko validation remains enabled outside pull requests" \
  "$disko_step" "github.event_name != 'pull_request' ||"
assert_contains "installer validation remains enabled outside pull requests" \
  "$installer_step" "github.event_name != 'pull_request' ||"

if ((failures > 0)); then
  echo "Results: $failures failure(s)"
  exit 1
fi
echo "Results: all PR validation path-selection tests passed"
