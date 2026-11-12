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
assert "PR check matrix is capped at eight concurrent runners" \
  "grep -q 'max-parallel: 8' '$REPO_ROOT/.github/workflows/pr-validation.yml'"
assert "PR check shards contain at most three checks" \
  "grep -q 'batchSize:3' '$REPO_ROOT/.github/workflows/pr-validation.yml'"
assert "three-check PR shards have a twenty-five-minute budget" \
  "grep -q 'timeout-minutes: 25' '$REPO_ROOT/.github/workflows/pr-validation.yml'"
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
assert "main build submits all configs in one Nix invocation" \
  "grep -q 'nix build --no-link.*installables' \\
    '$REPO_ROOT/.github/workflows/main-build.yml'"
assert "main build warms the bootstrap deployment closure" \
  "grep -q 'select(test(\"^installer-\") | not)' \\
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
