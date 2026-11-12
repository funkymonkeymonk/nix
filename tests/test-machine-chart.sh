#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repo_root"
devenv_file="$repo_root/devenv.nix"
chart_expression_file="$repo_root/library/machines/chart-expression.nix"

assert_contains() {
  local file="$1" expected="$2" label="$3"
  if ! grep -Fq -- "$expected" "$file"; then
    printf 'FAIL: %s (missing %q in %s)\n' "$label" "$expected" "$file" >&2
    exit 1
  fi
}

assert_output_contains() {
  local output="$1" expected="$2" label="$3"
  if ! grep -Fq -- "$expected" <<< "$output"; then
    printf 'FAIL: %s (missing %q)\n' "$label" "$expected" >&2
    exit 1
  fi
}

assert_contains "$devenv_file" 'exec = "bash scripts/machine-chart.sh";' \
  'the Devenv task delegates to the standalone renderer'
assert_contains "$chart_expression_file" 'definitionsWithLocations' \
  'system packages are attributed to their defining modules'
assert_contains "$chart_expression_file" 'homebrewOptions.brews.definitionsWithLocations' \
  'Homebrew formulae are included under their module'
assert_contains "$chart_expression_file" 'homebrewOptions.casks.definitionsWithLocations' \
  'Homebrew casks are included under their module'
assert_contains "$chart_expression_file" 'homebrewOptions.masApps.definitionsWithLocations' \
  'Mac App Store apps are included under their module'
assert_contains "$repo_root/scripts/machine-chart.sh" 'MACHINE_CHART_ACTION=names nix eval' \
  'the renderer can discover all flake machine names'
assert_contains "$repo_root/scripts/machine-chart.sh" 'MACHINE_CHART_PACKAGES=false' \
  'the renderer handles package evaluation failures gracefully'
assert_contains "$chart_expression_file" 'lib.concatStringsSep' 'Nix renders the tree output'

all_chart=$(DEVENV_TASK_INPUT='{"machine":""}' bash scripts/machine-chart.sh)
expected_machines=$(nix eval --impure --option builders "" --json --expr '
  let
    flake = builtins.getFlake (toString ./.);
  in
    builtins.attrNames flake.nixosConfigurations
    ++ builtins.attrNames flake.darwinConfigurations
')
while IFS= read -r machine; do
  assert_output_contains "$all_chart" "$machine (" "default output includes $machine"
done < <(jq -r '.[]' <<< "$expected_machines")
assert_output_contains "$all_chart" 'Formulae (modules/services/omlx/darwin.nix)' \
  'Homebrew formula is grouped by its source module'
assert_output_contains "$all_chart" 'Casks (modules/roles/homebrew.nix)' \
  'Homebrew casks are grouped by their role'
assert_output_contains "$all_chart" 'Package lists unavailable' \
  'cross-platform package fallback is shown'

selected_chart=$(DEVENV_TASK_INPUT='{"machine":"MegamanX"}' bash scripts/machine-chart.sh)
assert_output_contains "$selected_chart" 'MegamanX (MegamanX, aarch64-darwin)' \
  'machine selection renders the chosen machine'
if grep -Fq 'bootstrap (' <<< "$selected_chart"; then
  echo 'FAIL: selecting one machine must omit all other machines' >&2
  exit 1
fi

printf 'Machine chart Nix task tests passed.\n'
