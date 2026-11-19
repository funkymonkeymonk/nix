#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0
FAIL=0

assert() {
  local desc="$1"
  local cmd="$2"
  if eval "$cmd" 2>/dev/null; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc"
    FAIL=$((FAIL + 1))
  fi
}

assert_exact_line() {
  local desc="$1"
  local block="$2"
  local expected="$3"
  if grep -Fxq -- "$expected" <<< "$block"; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc"
    FAIL=$((FAIL + 1))
  fi
}

extract_job() {
  local job="$1"
  awk -v target="  $job:" '
    $0 == target { active = 1; print; next }
    active && /^  [^ ]/ { exit }
    active { print }
  ' "$REPO_ROOT/.github/workflows/pr-validation.yml"
}

extract_job_condition() {
  awk '
    /^    if: / { active = 1; print; next }
    active && /^      / { print; next }
    active { exit }
  '
}

extract_step() {
  local step="$1"
  awk -v target="      - name: $step" '
    $0 == target { active = 1; print; next }
    active && /^      - name:/ { exit }
    active { print }
  '
}
echo "=== CI Workflow Tests ==="

assert "workflows do not invoke the retired OpenCode comment action" \
  "! grep -Fq 'sst/opencode/github@github-v1' '$REPO_ROOT'/.github/workflows/*.yml"

# Require the selected Node 24 releases in every workflow that uses them.
for action_ref in \
  'actions/checkout@v6' \
  'cachix/cachix-action@v17' \
  'DeterminateSystems/nix-installer-action@v23' \
  'DeterminateSystems/magic-nix-cache-action@v14' \
  'DeterminateSystems/flakehub-push@v7' \
  'actions/cache@v5' \
  'actions/cache/restore@v5' \
  'actions/cache/save@v5' \
  'actions/upload-artifact@v6' \
  'actions/download-artifact@v7' \
  'dorny/paths-filter@v4' \
  'softprops/action-gh-release@v3'; do
  action="${action_ref%@*}"
  assert "$action uses the selected Node 24 ref" \
    "awk -v action='$action' -v expected='$action_ref' '
      /uses:/ {
        line = \$0
        sub(/^.*uses:[[:space:]]*[\"\047]?/, \"\", line)
        sub(/[\"\047[:space:]#].*$/, \"\", line)
        split(line, parts, \"@\")
        if (parts[1] == action) { found = 1; if (line != expected) bad = 1 }
      }
      END { exit !(found && !bad) }
    ' '$REPO_ROOT'/.github/workflows/*.yml"
done

assert "all Ubuntu runners use explicit maintained 24.04 labels" \
  "awk '
    /runs-on:/ && /ubuntu/ {
      line = \$0
      sub(/^.*runs-on:[[:space:]]*[\"\047]?/, \"\", line)
      sub(/[\"\047[:space:]#].*$/, \"\", line)
      found = 1
      if (line != \"ubuntu-24.04\" && line != \"ubuntu-24.04-arm\") bad = 1
    }
    END { exit !(found && !bad) }
  ' '$REPO_ROOT'/.github/workflows/*.yml"

# Test: every Nix installer invocation raises retries for transient cache downloads.
for workflow in "$REPO_ROOT"/.github/workflows/*.yml; do
  if grep -q 'uses: DeterminateSystems/nix-installer-action' "$workflow"; then
    installer_count=$(grep -c 'uses: DeterminateSystems/nix-installer-action' "$workflow")
    retry_count=$(grep -cF 'download-attempts = 10' "$workflow" || true)
    assert "$(basename "$workflow") configures ten Nix download attempts for every installer" \
      "[[ $installer_count -eq $retry_count ]]"
  fi
done

# Test: all CI workflows have permissions blocks
for wf in build-iso.yml cache-maintenance.yml extended-validation.yml main-build.yml overlay-upstream-sources.yml pr-validation.yml; do
  assert "$wf has permissions block" \
    "grep -q '^permissions:' '$REPO_ROOT/.github/workflows/$wf'"
done

# Test: shared facter stub script exists and is executable
assert "facter stub script exists" \
  "test -f '$REPO_ROOT/.github/scripts/create-facter-stub.sh'"
assert "facter stub script is executable" \
  "test -x '$REPO_ROOT/.github/scripts/create-facter-stub.sh'"

# Test: no hardcoded config lists remain in pr-validation.yml
assert "no hardcoded darwin list" \
  "! grep -q 'DARWIN_CHANGED=.*core.*darwin-server.*wweaver' \
  '$REPO_ROOT/.github/workflows/pr-validation.yml'"
assert "no hardcoded nixos list" \
  "! grep -q 'NIXOS_CHANGED=.*bootstrap.*installer-iso.*type-server' \
  '$REPO_ROOT/.github/workflows/pr-validation.yml'"

# Test: pr-validation uses dynamic discovery
assert "pr-validation uses nix eval for darwin" \
  "grep -q 'nix eval.*darwinConfigurations' \
  '$REPO_ROOT/.github/workflows/pr-validation.yml'"
assert "pr-validation uses nix eval for nixos" \
  "grep -q 'nix eval.*nixosConfigurations' \
  '$REPO_ROOT/.github/workflows/pr-validation.yml'"

# Test: inline facter stubs are replaced with script calls in pr-validation.yml
assert "pr-validation calls facter stub script (not inline)" \
  "grep -q 'bash .github/scripts/create-facter-stub.sh' \
  '$REPO_ROOT/.github/workflows/pr-validation.yml'"

# Test: inline facter stub replaced with script call in main-build.yml
assert "main-build calls facter stub script (not inline)" \
  "grep -q 'bash .github/scripts/create-facter-stub.sh' \
  '$REPO_ROOT/.github/workflows/main-build.yml'"

# Test: CI check planning and builds bypass the full Devenv package profile.
assert "PR workflow plans changed checks with the standalone Nix helper" \
  "grep -q 'bash .github/scripts/ci-checks.sh plan non-vm' \
  '$REPO_ROOT/.github/workflows/pr-validation.yml'"
assert "PR workflow builds check shards with the standalone Nix helper" \
  "grep -q 'bash .github/scripts/ci-checks.sh build non-vm' \
  '$REPO_ROOT/.github/workflows/pr-validation.yml'"
assert "PR check discovery selects checks from changed files" \
  "grep -q 'select-pr-checks.sh' \
    '$REPO_ROOT/.github/workflows/pr-validation.yml'"
assert "PR workflow runs PR validation path-selection regression tests" \
  "grep -q 'bash tests/test-ci-pr-validation-selection.sh' \
    '$REPO_ROOT/.github/workflows/pr-validation.yml'"
assert "non-VM PR checks run when selected prefixes are non-empty" \
  "grep -Fq \"check-prefixes != '[]'\" \
    '$REPO_ROOT/.github/workflows/pr-validation.yml'"
assert "secret manifest changes trigger config checks" \
  "grep -q \"secretspec.toml\" \
    '$REPO_ROOT/.github/workflows/pr-validation.yml'"
assert "PR workflow runs changed-check selector regression tests" \
  "grep -q 'bash tests/test-ci-change-selection.sh' \
    '$REPO_ROOT/.github/workflows/pr-validation.yml'"
assert "CI helper tests run only when CI tooling changes" \
  "grep -q 'ci-helper-files:' \
    '$REPO_ROOT/.github/workflows/pr-validation.yml' \
    && grep -q \"if: needs.changes.outputs.ci-helper-files == 'true'\" \
      '$REPO_ROOT/.github/workflows/pr-validation.yml'"
assert "CI helper regression tests run independently from lint" \
  "awk '/^  ci-helper-tests:/,/^  changes:/' \
    '$REPO_ROOT/.github/workflows/pr-validation.yml' \
    | grep -q 'needs: \[changes\]' \
    && ! awk '/^  ci-helper-tests:/,/^  changes:/' \
      '$REPO_ROOT/.github/workflows/pr-validation.yml' \
      | grep -q 'needs:.*lint'"
assert "CI helper regression tests do not install Devenv" \
  "! awk '/^  ci-helper-tests:/,/^  changes:/' \
    '$REPO_ROOT/.github/workflows/pr-validation.yml' \
    | grep -q 'devenv'"
assert "overlay source checker changes trigger its CI regression test" \
  "grep -q 'scripts/check-overlay-upstream-urls.sh' \
    '$REPO_ROOT/.github/workflows/pr-validation.yml' \
    && grep -q 'scripts/overlay-source-urls.nix' \
      '$REPO_ROOT/.github/workflows/pr-validation.yml'"
assert "PR workflow keeps VM smoke checks independent" \
  "grep -q 'bash .github/scripts/ci-checks.sh build vm-pr' \
    '$REPO_ROOT/.github/workflows/pr-validation.yml'"
test_validate_job="$(extract_job test-and-validate)"
discover_targets_job="$(extract_job discover-targets)"
discover_targets_condition="$(extract_job_condition <<< "$discover_targets_job")"
test_validate_condition="$(extract_job_condition <<< "$test_validate_job")"
assert_exact_line "discover-targets uses a folded bare condition" \
  "$discover_targets_condition" "    if: >-"
assert_exact_line "discover-targets condition is not a truthy interpolation" \
  "$discover_targets_condition" "      needs.changes.outputs.nix-files == 'true' ||"
assert_exact_line "discover-targets condition includes workflow changes" \
  "$discover_targets_condition" "      needs.changes.outputs.workflows == 'true'"
assert "discover-targets condition has no expression wrapper" \
  "! grep -Fq '\${{' <<< \"\$discover_targets_condition\""
assert_exact_line "test-and-validate uses a folded bare condition" \
  "$test_validate_condition" "    if: >-"
assert_exact_line "test-and-validate condition requires selected prefixes" \
  "$test_validate_condition" "      needs.changes.outputs.check-prefixes != '[]' &&"
assert_exact_line "test-and-validate condition requires a non-empty matrix" \
  "$test_validate_condition" "      needs.discover-checks.outputs.matrix != ''"
assert "test-and-validate condition has no expression wrapper" \
  "! grep -Fq '\${{' <<< \"\$test_validate_condition\""
discover_checks_job="$(extract_job discover-checks)"
check_planning_step="$(extract_step 'Plan changed PR checks' <<< "$discover_checks_job")"
assert_exact_line "test-and-validate caps concurrency at exactly six runners" \
  "$test_validate_job" "      max-parallel: 6"
assert_exact_line "PR planner batches exactly four checks" \
  "$check_planning_step" "            '{batchSize:4,checkPrefixes:\$prefixes}')"
assert_exact_line "four-check PR shards keep a twenty-five-minute budget" \
  "$test_validate_job" "    timeout-minutes: 25"
assert "PR workflow omits full role-package VM tests" \
  "! grep -Eq 'vm-role-(foundation|developer)' \
  '$REPO_ROOT/.github/workflows/pr-validation.yml'"
assert "PR validation does not install Devenv for lint or check jobs" \
  "! grep -q 'github:cachix/devenv' \
    '$REPO_ROOT/.github/workflows/pr-validation.yml'"
assert "PR workflows do not invoke the external build-checks script" \
  "! grep -R -q 'build-checks.sh' \\
    '$REPO_ROOT/.github/workflows' '$REPO_ROOT/devenv.nix'"
assert "PR Cachix access is read-only" \
  "! grep -q 'CACHIX_AUTH_TOKEN' \\
    '$REPO_ROOT/.github/workflows/pr-validation.yml' \\
    && grep -q 'skipPush: true' \\
    '$REPO_ROOT/.github/workflows/pr-validation.yml'"
assert "PR build jobs use the rate-limit-resistant Hestia cache" \
  "grep -q 'Mic92/hestia@v3.1.0' \\
    '$REPO_ROOT/.github/workflows/pr-validation.yml' \\
    && grep -q 'upstream-cache-filter: true' \\
    '$REPO_ROOT/.github/workflows/pr-validation.yml' \\
    && ! grep -q 'magic-nix-cache-action' \\
    '$REPO_ROOT/.github/workflows/pr-validation.yml'"
assert "Hestia cache outages do not block PR jobs" \
  "awk '/- name: Hestia Nix Cache/ { active=1; steps++; next } active && /continue-on-error: true/ { tolerated++ } active && /upstream-cache-filter:/ { active=0 } END { exit !(steps == 2 && tolerated == 2) }' \
    '$REPO_ROOT/.github/workflows/pr-validation.yml'"
assert "PR test shard frees runner disk before Nix setup" \
  "awk '/^  test-and-validate:/,/^  build-report:/' \
    '$REPO_ROOT/.github/workflows/pr-validation.yml' \
    | awk '/Free up disk space/ { free=NR } /name: Install Nix/ { install=NR } END { exit !(free && install && free < install) }'"
assert "PR test shard cleanup removes unused runner toolchains and Docker images" \
  "awk '/^  test-and-validate:/,/^  build-report:/' \
    '$REPO_ROOT/.github/workflows/pr-validation.yml' \
    | grep -q '/usr/share/dotnet' \
    && awk '/^  test-and-validate:/,/^  build-report:/' \
      '$REPO_ROOT/.github/workflows/pr-validation.yml' \
      | grep -q 'docker system prune -af'"
assert "PR test shard records disk space after cleanup" \
  "awk '/^  test-and-validate:/,/^  build-report:/' \
    '$REPO_ROOT/.github/workflows/pr-validation.yml' \
    | grep -q 'df -h'"
assert "PR VM smoke job frees disk before Nix setup" \
  "awk '/^  vm-tests:/,/^  test-and-validate:/' \
    '$REPO_ROOT/.github/workflows/pr-validation.yml' \
    | awk '/Free up disk space/ { free=NR } /name: Install Nix/ { install=NR } END { exit !(free && install && free < install) }'"
assert "PR VM smoke job removes unused runner toolchains and Docker images" \
  "awk '/^  vm-tests:/,/^  test-and-validate:/' \
    '$REPO_ROOT/.github/workflows/pr-validation.yml' \
    | grep -q '/usr/share/dotnet' \
    && awk '/^  vm-tests:/,/^  test-and-validate:/' \
      '$REPO_ROOT/.github/workflows/pr-validation.yml' \
      | grep -q 'docker system prune -af'"
assert "PR VM smoke job reports disk usage after cleanup" \
  "awk '/^  vm-tests:/,/^  test-and-validate:/' \
    '$REPO_ROOT/.github/workflows/pr-validation.yml' \
    | grep -q 'df -h'"
assert "PR workflow runs CI workflow regression tests" \
  "grep -q 'bash tests/test-ci-workflows.sh' \
  '$REPO_ROOT/.github/workflows/pr-validation.yml'"
assert "module coverage is not run unconditionally for every PR" \
  "! grep -q 'module coverage regression guard' \
    '$REPO_ROOT/.github/workflows/pr-validation.yml'"
assert "PR workflow runs CI check selector tests" \
  "grep -q 'bash tests/test-ci-check-groups.sh' \
  '$REPO_ROOT/.github/workflows/pr-validation.yml'"
assert "PR workflow runs derivation cache regression tests" \
  "grep -q 'bash tests/test-ci-config-cache.sh' \\
    '$REPO_ROOT/.github/workflows/pr-validation.yml'"
assert "PR lint remains fast and does not install the full devenv CLI" \
  "grep -q 'run: bash .github/scripts/lint.sh' \
    '$REPO_ROOT/.github/workflows/pr-validation.yml' \\
    && ! grep -q 'github:cachix/devenv/.*#devenv' \\
      '$REPO_ROOT/.github/workflows/pr-validation.yml'"

# Test: extended package and role checks use direct Nix calls without Devenv.
assert "extended package workflow uses the standalone check helper" \
  "grep -q 'bash .github/scripts/ci-checks.sh build extended' \\
    '$REPO_ROOT/.github/workflows/extended-validation.yml'"
assert "extended VM workflow uses the standalone check helper" \
  "grep -q 'bash .github/scripts/ci-checks.sh build vm-extended' \\
    '$REPO_ROOT/.github/workflows/extended-validation.yml'"
assert "extended CI workflow does not install or run Devenv" \
  "! grep -q 'devenv' '$REPO_ROOT/.github/workflows/extended-validation.yml'"
assert "flake update workflow does not install Devenv unnecessarily" \
  "! grep -q 'devenv' '$REPO_ROOT/.github/workflows/flake-update.yml'"
assert "weekly release refreshes hashes without Devenv" \
  "grep -q 'bash scripts/refresh-fixed-output-hashes.sh' \\
    '$REPO_ROOT/.github/workflows/weekly-release.yml' \\
    && ! grep -q 'devenv' '$REPO_ROOT/.github/workflows/weekly-release.yml'"
assert "local extended package task selects the extended check group" \
  "grep -q '\"ci:checks:extended\" = ciChecksTask' '$REPO_ROOT/devenv.nix' \\
    && grep -q 'group = \"extended\";' '$REPO_ROOT/devenv.nix'"
assert "local extended VM task selects full role-package checks" \
  "grep -q '\"ci:checks:vm-extended\" = ciChecksTask' '$REPO_ROOT/devenv.nix' \\
    && grep -q 'group = \"vm-extended\";' '$REPO_ROOT/devenv.nix' \\
    && grep -q 'vm-role-foundation.*vm-role-developer' '$REPO_ROOT/.github/scripts/ci-checks.sh'"
assert "extended validation is manually dispatchable, main-only, and cancellable" \
  "grep -q '^  workflow_dispatch:' '$REPO_ROOT/.github/workflows/extended-validation.yml' \\
    && ! grep -q '^  schedule:' '$REPO_ROOT/.github/workflows/extended-validation.yml' \\
    && grep -q \"github.ref == 'refs/heads/main'\" \\
      '$REPO_ROOT/.github/workflows/extended-validation.yml' \\
    && grep -q 'cancel-in-progress: true' \\
      '$REPO_ROOT/.github/workflows/extended-validation.yml'"
assert "extended validation populates Cachix from trusted workflow" \
  "grep -q 'secrets.CACHIX_AUTH_TOKEN' \\
    '$REPO_ROOT/.github/workflows/extended-validation.yml' \\
    && ! grep -q '^  pull_request:' \\
    '$REPO_ROOT/.github/workflows/extended-validation.yml' \\
    && grep -q 'refs/heads/main' \\
    '$REPO_ROOT/.github/workflows/extended-validation.yml'"

# Test: derivation cache records the current configurations, including additions.
assert "derivation cache compares discovered Darwin configs" \
  "grep -q 'steps.discover.outputs.darwin-configs' \\
    '$REPO_ROOT/.github/workflows/pr-validation.yml'"
assert "derivation cache compares discovered NixOS configs" \
  "grep -q 'steps.discover.outputs.nixos-configs' \\
    '$REPO_ROOT/.github/workflows/pr-validation.yml'"
assert "derivation cache helper is used by discovery" \
  "grep -q 'bash .github/scripts/check-config-changes.sh' \\
    '$REPO_ROOT/.github/workflows/pr-validation.yml'"
assert "derivation cache staging is promoted before save" \
  "grep -q 'if mv ' \\
    '$REPO_ROOT/.github/scripts/check-config-changes.sh'"
assert "cache save is skipped when derivation discovery failed" \
  "grep -q \"steps.check-changes.outcome == 'success'\" \\
    '$REPO_ROOT/.github/workflows/pr-validation.yml'"

# Test: full validation runs only on the newest main workflow run without
# realizing the complete Devenv package profile.
assert "main workflow cancels superseded runs" \
  "grep -q 'cancel-in-progress: true' \
    '$REPO_ROOT/.github/workflows/main-build.yml'"
assert "main workflow runs all Nix checks directly" \
  "grep -q 'nix flake check --max-jobs auto' \
    '$REPO_ROOT/.github/workflows/main-build.yml'"
assert "main workflow keeps platform deprecation checks" \
  "grep -q 'bash tests/test-platform-deprecation-warnings.sh' \
    '$REPO_ROOT/.github/workflows/main-build.yml'"
assert "main workflow tests the machine chart without Devenv" \
  "grep -q 'bash tests/test-machine-chart.sh' \
    '$REPO_ROOT/.github/workflows/main-build.yml'"
assert "main full test suite does not invoke Devenv tasks" \
  "! grep -q 'devenv tasks run' \
    '$REPO_ROOT/.github/workflows/main-build.yml'"
assert "main workflow does not install Devenv for the full test suite" \
  "! grep -q 'github:cachix/devenv/.*#devenv' \
    '$REPO_ROOT/.github/workflows/main-build.yml'"
assert "full test suite is restricted to main" \
  "grep -q \"if: github.event_name == 'workflow_dispatch' && github.ref == 'refs/heads/main'\" \
    '$REPO_ROOT/.github/workflows/main-build.yml'"
full_suite_job="$(awk '
  /^  full-test-suite:/ { active = 1 }
  active && /^  [^ ]/ && !/^  full-test-suite:/ { exit }
  active { print }
' "$REPO_ROOT/.github/workflows/main-build.yml")"
full_suite_condition="$(sed -n 's/^    if: //p' <<< "$full_suite_job")"
full_suite_runs_for() {
  local event_name="$1"
  local ref="$2"
  local condition="$full_suite_condition"
  condition=${condition//github.event_name/\"$event_name\"}
  condition=${condition//github.ref/\"$ref\"}
  eval "[[ $condition ]]"
}
assert "main full test suite skips routine push events" \
  "! full_suite_runs_for push refs/heads/main"
assert "main full test suite runs on manual main dispatch" \
  "full_suite_runs_for workflow_dispatch refs/heads/main"

# Test: deploy builds submit whole configuration sets to Nix and Cachix.
main_workflow="$REPO_ROOT/.github/workflows/main-build.yml"
main_job() {
  awk -v target="  $1:" '
    $0 == target { active = 1; print; next }
    active && /^  [^ ]/ { exit }
    active { print }
  ' "$main_workflow"
}
main_discovery="$(main_job discover-targets)"
assert_exact_line "manual force selection feeds change detection" \
  "$(extract_step 'Check which configs changed' <<< "$main_discovery")" \
  '          FORCE_REBUILD: ${{ inputs.force-rebuild || false }}'
main_health="$(main_job cache-health)"
main_save="$(extract_step 'Save successful derivation cache' <<< "$main_health")"
assert "main discovery compares derivations using a dedicated successful-build cache" \
  "grep -q 'check-config-changes.sh' <<< \"\$main_discovery\" && \
   grep -q 'main-build-drv-' <<< \"\$main_discovery\" && \
   ! grep -q 'actions/cache/save' <<< \"\$main_discovery\""
for platform in darwin linux linux-arm; do
  main_build="$(main_job "build-$platform")"
  case "$platform" in
    darwin) output=darwin-changed; runner=macos-latest ;;
    linux) output=nixos-changed; runner=ubuntu-24.04 ;;
    linux-arm) output=nixos-arm-changed; runner=ubuntu-24.04-arm ;;
  esac
  assert "main $platform builds only selected configurations on its native runner" \
    "grep -q 'needs:.*discover-targets' <<< \"\$main_build\" && \
     grep -q 'needs.discover-targets.outputs.$output' <<< \"\$main_build\" && \
     grep -q 'runs-on: $runner' <<< \"\$main_build\" && \
     grep -q 'No .*configurations.*' <<< \"\$main_build\" && \
     grep -q 'exit 0' <<< \"\$main_build\""
done

# Execute each real build step with controlled selection outputs. Stub only the
# external Nix build, recording its arguments so invalid lists cannot hide a
# partial build and valid lists must reach the correct platform installable.
selection_tmp="$(mktemp -d)"
trap 'rm -rf "$selection_tmp"' EXIT
mkdir -p "$selection_tmp/bin"
extract_step 'Discover configurations' <<< "$main_discovery" | sed -n '/^        run: |$/,$p' |
  sed '1d; s/^          //' > "$selection_tmp/discover"
cat > "$selection_tmp/bin/nix" <<'EVAL_STUB'
#!/usr/bin/env bash
case "$*" in
  *darwinConfigurations*) printf '%s\n' "$DARWIN_JSON" ;;
  *nixosConfigurations*) printf '%s\n' "$NIXOS_JSON" ;;
  *) exit 1 ;;
esac
EVAL_STUB
chmod +x "$selection_tmp/bin/nix"
run_discovery() {
  : > "$selection_tmp/inventory"
  DARWIN_JSON="$1" NIXOS_JSON="$2" GITHUB_OUTPUT="$selection_tmp/inventory" \
    PATH="$selection_tmp/bin:$PATH" bash "$selection_tmp/discover"
}
valid='["test-host"]'
for invalid in '' '[]' '{"host":"test-host"}' '["bad name"]' '[] ["test-host"]'; do
  assert "Darwin discovery rejects $(printf '%q' "$invalid")" \
    '! run_discovery "$invalid" "$valid" && [[ ! -s "$selection_tmp/inventory" ]]'
  assert "NixOS discovery rejects $(printf '%q' "$invalid")" \
    '! run_discovery "$valid" "$invalid" && [[ ! -s "$selection_tmp/inventory" ]]'
done
assert "discovery rejects an empty eligible NixOS inventory" \
  '! run_discovery "$valid" "[\"installer-iso\"]"'
assert "discovery emits eligible platform inventories" \
  'run_discovery "$valid" "[\"installer-iso\",\"test-host\"]" &&
   grep -Fxq "darwin-configs=$valid" "$selection_tmp/inventory" &&
   grep -Fxq "nixos-configs=$valid" "$selection_tmp/inventory"'
cat > "$selection_tmp/bin/nix" <<'NIX_STUB'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$NIX_ARGS"
printf '%s\n' /nix/store/test-output
NIX_STUB
cat > "$selection_tmp/bin/cachix" <<'CACHIX_STUB'
#!/usr/bin/env bash
[[ "$*" == 'push funkymonkeymonk' && "$CACHIX_AUTH_TOKEN" == test-token ]] &&
  grep -Fxq /nix/store/test-output
CACHIX_STUB
chmod +x "$selection_tmp/bin/"{nix,cachix}
run_main_selection() {
  : > "$selection_tmp/nix-args"
  TEST_CONFIGS="$1" CACHIX_AUTH_TOKEN="${2-test-token}" NIX_ARGS="$selection_tmp/nix-args" \
    GITHUB_OUTPUT="$selection_tmp/github-output" PATH="$selection_tmp/bin:$PATH" \
    bash "$selection_tmp/build-step" > "$selection_tmp/stdout" 2> "$selection_tmp/stderr"
}
for platform in darwin linux linux-arm; do
  main_build="$(main_job "build-$platform")"
  case "$platform" in
    darwin) step='Build Darwin configurations (push to Cachix)'; expected='.#darwinConfigurations.test-host.system' ;;
    linux) step='Build Linux configurations (push to Cachix)'; expected='.#nixosConfigurations.test-host.config.system.build.toplevel' ;;
    linux-arm) step='Build ARM Linux configurations (push to Cachix)'; expected='.#nixosConfigurations.test-host.config.system.build.toplevel' ;;
  esac
  assert_exact_line "$platform build receives the push credential" \
    "$(extract_step "$step" <<< "$main_build")" \
    '          CACHIX_AUTH_TOKEN: ${{ secrets.CACHIX_AUTH_TOKEN }}'
  extract_step "$step" <<< "$main_build" | awk '
    /^        run: \|$/ { active=1; next }
    active && /^          / { sub(/^          /, ""); print; next }
    active { exit }
  ' | sed 's/^CONFIGS=.*/CONFIGS="$TEST_CONFIGS"/' > "$selection_tmp/build-step"
  for invalid in '' '[' 'null' '{}' '"target"' '[1]' '[""]' '["bad name"]' '["test-host"] [' '[] []'; do
    assert "$platform rejects invalid selection $(printf '%q' "$invalid")" \
      "! run_main_selection \"\$invalid\" && [[ ! -s \"\$selection_tmp/nix-args\" ]]"
  done
  assert "$platform accepts an empty array without building" \
    "run_main_selection '[]' && [[ ! -s \"\$selection_tmp/nix-args\" ]]"
  assert "$platform rejects a missing credential even with no selected configs" \
    "! run_main_selection '[]' ''"
  assert "$platform push rejection fails the build job" \
    "! run_main_selection '[\"test-host\"]' rejected-token"
  assert "$platform builds the selected installable" \
    "run_main_selection '[\"test-host\"]' && grep -Fxq -- \"\$expected\" \"\$selection_tmp/nix-args\""
done
assert "main candidate cache is published only after all build jobs pass" \
  "grep -q 'needs:.*discover-targets.*build-darwin.*build-linux.*build-linux-arm' <<< \"\$main_health\" && \
   grep -q 'actions/download-artifact@v7' <<< \"\$main_health\" && \
   grep -q 'actions/cache/save@v5' <<< \"\$main_health\" && \
   grep -q 'success()' <<< \"\$main_save\" && \
   grep -q 'needs.discover-targets.result == .success.' <<< \"\$main_save\" && \
   grep -q 'needs.build-darwin.result == .success.' <<< \"\$main_save\" && \
   grep -q 'needs.build-linux.result == .success.' <<< \"\$main_save\" && \
   grep -q 'needs.build-linux-arm.result == .success.' <<< \"\$main_save\""
# Exercise the actual save condition with failed, skipped, and cancelled jobs.
save_condition="$(awk '/^        if: >-/{active=1; next} active && /^          /{printf "%s ", $0; next} active{exit}' <<< "$main_save")"
save_condition=${save_condition//success\(\)/\"\$step_result\" == \"success\"}
save_condition=${save_condition//needs.discover-targets.result/\"\$discovery\"}
save_condition=${save_condition//needs.build-darwin.result/\"\$darwin\"}
save_condition=${save_condition//needs.build-linux.result/\"\$linux\"}
save_condition=${save_condition//needs.build-linux-arm.result/\"\$arm\"}
save_allowed() { eval "[[ $save_condition ]]"; }
step_result=success discovery=success darwin=success linux=success arm=success
assert "successful builds allow candidate publication" "save_allowed"
for job in discovery darwin linux arm step_result; do
  for result in failure skipped cancelled; do
    printf -v "$job" '%s' "$result"
    assert "$job $result prevents candidate publication" "! save_allowed"
    printf -v "$job" '%s' success
  done
done
assert "main build submits all configs in one Nix invocation" \
  "grep -q 'nix build --no-link.*installables' \\
    '$REPO_ROOT/.github/workflows/main-build.yml'"
assert "main build warms the bootstrap deployment closure" \
  "grep -q 'test(\"^installer-\") | not' \\
    '$REPO_ROOT/.github/workflows/main-build.yml'"
assert "deploy machines use the shared Cachix substituter" \
  "grep -q 'https://funkymonkeymonk.cachix.org' \\
    '$REPO_ROOT/modules/common/cachix.nix'"
assert "overlay source check is weekly and manually dispatchable" \
  "grep -q '^  workflow_dispatch:' '$REPO_ROOT/.github/workflows/overlay-upstream-sources.yml' \\
    && grep -q '^  schedule:' '$REPO_ROOT/.github/workflows/overlay-upstream-sources.yml'"
assert "overlay source workflow runs the uncached URL checker" \
  "grep -q 'bash scripts/check-overlay-upstream-urls.sh' \\
    '$REPO_ROOT/.github/workflows/overlay-upstream-sources.yml' \\
    && ! grep -q 'cachix-action' \\
      '$REPO_ROOT/.github/workflows/overlay-upstream-sources.yml'"
assert "overlay source URL checks are available as a local task" \
  "grep -q 'check:overlay-upstreams' '$REPO_ROOT/devenv.nix'"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]] || exit 1
