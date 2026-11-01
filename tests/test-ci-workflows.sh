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

# Test: all CI workflows have permissions blocks
for wf in build-iso.yml cache-maintenance.yml extended-validation.yml main-build.yml pr-validation.yml; do
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

# Test: PR checks are sharded by devenv tasks and parallelized across runners.
assert "PR workflow generates its check matrix through devenv" \
  "grep -q 'devenv tasks run ci:checks:pr-plan' \
  '$REPO_ROOT/.github/workflows/pr-validation.yml'"
assert "PR workflow builds each shard through devenv" \
  "grep -q 'devenv tasks run ci:checks:pr-shard' \
  '$REPO_ROOT/.github/workflows/pr-validation.yml'"
assert "PR check matrix is capped at eight concurrent runners" \
  "grep -q 'max-parallel: 8' '$REPO_ROOT/.github/workflows/pr-validation.yml'"
assert "each PR check shard has a twenty-minute budget" \
  "grep -q 'timeout-minutes: 20' '$REPO_ROOT/.github/workflows/pr-validation.yml'"
assert "PR workflow runs smoke VM checks through devenv" \
  "grep -q 'devenv tasks run ci:checks:vm-pr' \
  '$REPO_ROOT/.github/workflows/pr-validation.yml'"
assert "PR workflow omits full role-package VM tests" \
  "! grep -Eq 'vm-role-(foundation|developer)' \
  '$REPO_ROOT/.github/workflows/pr-validation.yml'"
assert "PR workflows do not invoke the external build-checks script" \
  "! grep -R -q 'build-checks.sh' \\
    '$REPO_ROOT/.github/workflows' '$REPO_ROOT/devenv.nix'"
assert "PR Cachix access is read-only" \
  "! grep -q 'CACHIX_AUTH_TOKEN' \\
    '$REPO_ROOT/.github/workflows/pr-validation.yml' \\
    && grep -q 'skipPush: true' \\
    '$REPO_ROOT/.github/workflows/pr-validation.yml'"
assert "PR workflow runs CI workflow regression tests" \
  "grep -q 'bash tests/test-ci-workflows.sh' \
  '$REPO_ROOT/.github/workflows/pr-validation.yml'"
assert "PR workflow runs CI check selector tests" \
  "grep -q 'bash tests/test-ci-check-groups.sh' \
  '$REPO_ROOT/.github/workflows/pr-validation.yml'"
assert "PR workflow runs derivation cache regression tests" \
  "grep -q 'bash tests/test-ci-config-cache.sh' \\
    '$REPO_ROOT/.github/workflows/pr-validation.yml'"
assert "PR lint remains an independent fast check" \
  "grep -q 'run: bash .github/scripts/lint.sh' \
    '$REPO_ROOT/.github/workflows/pr-validation.yml' \\
    && grep -q '\$NIXPKGS#devenv' \\
    '$REPO_ROOT/.github/workflows/pr-validation.yml'"

# Test: expensive package and role checks remain covered on a trusted schedule.
assert "extended package workflow uses its devenv task" \
  "grep -q 'devenv tasks run ci:checks:extended' \\
    '$REPO_ROOT/.github/workflows/extended-validation.yml'"
assert "extended VM workflow uses its devenv task" \
  "grep -q 'devenv tasks run ci:checks:vm-extended' \\
    '$REPO_ROOT/.github/workflows/extended-validation.yml'"
assert "extended package task selects the extended check group" \
  "grep -q '\"ci:checks:extended\" = ciChecksTask' '$REPO_ROOT/devenv.nix' \\
    && grep -q 'group = \"extended\";' '$REPO_ROOT/devenv.nix'"
assert "extended VM task selects full role-package checks" \
  "grep -q '\"ci:checks:vm-extended\" = ciChecksTask' '$REPO_ROOT/devenv.nix' \\
    && grep -q 'group = \"vm-extended\";' '$REPO_ROOT/devenv.nix' \\
    && grep -q 'vm-role-foundation.*vm-role-developer' '$REPO_ROOT/devenv.nix'"
assert "extended validation is scheduled and manually dispatchable" \
  "grep -q '^  schedule:' '$REPO_ROOT/.github/workflows/extended-validation.yml' \\
    && grep -q '^  workflow_dispatch:' '$REPO_ROOT/.github/workflows/extended-validation.yml'"
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

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]] || exit 1
