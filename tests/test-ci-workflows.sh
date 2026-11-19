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

extract_step() {
  local step="$1"
  awk -v target="      - name: $step" '
    $0 == target { active = 1; print; next }
    active && /^      - name:/ { exit }
    active { print }
  '
}

echo "=== CI Workflow Tests ==="

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
  "grep -q \"if: github.ref == 'refs/heads/main'\" \
    '$REPO_ROOT/.github/workflows/main-build.yml'"

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
    linux) output=nixos-changed; runner=ubuntu-latest ;;
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
cat > "$selection_tmp/bin/nix" <<'NIX_STUB'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$NIX_ARGS"
NIX_STUB
chmod +x "$selection_tmp/bin/nix"
run_main_selection() {
  : > "$selection_tmp/nix-args"
  TEST_CONFIGS="$1" NIX_ARGS="$selection_tmp/nix-args" \
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
  assert "$platform builds the selected installable" \
    "run_main_selection '[\"test-host\"]' && grep -Fxq -- \"\$expected\" \"\$selection_tmp/nix-args\""
done
assert "main candidate cache is published only after all build jobs pass" \
  "grep -q 'needs:.*discover-targets.*build-darwin.*build-linux.*build-linux-arm' <<< \"\$main_health\" && \
   grep -q 'actions/download-artifact@v4' <<< \"\$main_health\" && \
   grep -q 'actions/cache/save@v4' <<< \"\$main_health\" && \
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
