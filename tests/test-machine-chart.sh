#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repo_root"
devenv_file="$repo_root/devenv.nix"

assert_contains() {
  local expected="$1" label="$2"
  if ! grep -Fq -- "$expected" "$devenv_file"; then
    printf 'FAIL: %s (missing %q in devenv.nix)\n' "$label" "$expected" >&2
    exit 1
  fi
}

assert_absent() {
  local unexpected="$1" label="$2"
  if grep -Fq -- "$unexpected" "$devenv_file"; then
    printf 'FAIL: %s (unexpected %q in devenv.nix)\n' "$label" "$unexpected" >&2
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

assert_contains 'machineChartExpression =' 'Nix expression for rendering the chart is embedded in devenv.nix'
assert_contains 'definitionsWithLocations' 'system packages are attributed to their defining modules'
assert_contains 'homebrewOptions.brews.definitionsWithLocations' 'Homebrew formulae are included under their module'
assert_contains 'homebrewOptions.casks.definitionsWithLocations' 'Homebrew casks are included under their module'
assert_contains 'homebrewOptions.masApps.definitionsWithLocations' 'Mac App Store apps are included under their module'
assert_contains 'MACHINE_CHART_ACTION=names' 'the task can discover all flake machine names'
assert_contains 'MACHINE_CHART_PACKAGES=false' 'the task handles package evaluation failures gracefully'
assert_contains 'lib.concatStringsSep' 'Nix renders the tree output'
assert_absent 'scripts/machine-chart.py' 'chart generation does not depend on an external Python script'

all_chart=$(devenv tasks run machines:chart --show-output 2>&1)
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
assert_output_contains "$all_chart" 'Formulae (modules/services/omlx/darwin.nix)' 'Homebrew formula is grouped by its source module'
assert_output_contains "$all_chart" 'Casks (modules/roles/homebrew.nix)' 'Homebrew casks are grouped by their role'
assert_output_contains "$all_chart" 'Package lists unavailable' 'cross-platform package fallback is shown'

selected_chart=$(devenv tasks run machines:chart --input machine=MegamanX --show-output 2>&1)
assert_output_contains "$selected_chart" 'MegamanX (MegamanX, aarch64-darwin)' 'machine selection renders the chosen machine'
if grep -Fq 'bootstrap (' <<< "$selected_chart"; then
  echo 'FAIL: selecting one machine must omit all other machines' >&2
  exit 1
fi

printf 'Machine chart Nix task tests passed.\n'
