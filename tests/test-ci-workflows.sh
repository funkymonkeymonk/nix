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

# Test: all 4 workflows have permissions blocks
for wf in build-iso.yml cache-maintenance.yml main-build.yml pr-validation.yml; do
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

# Test: CI check batching invokes Nix once per suite and keeps VM checks isolated.
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT
mkdir -p "$tmp/bin"
cat > "$tmp/bin/nix" <<'MOCK_NIX'
#!/usr/bin/env bash
set -euo pipefail
printf 'CALL' >> "$NIX_CALL_LOG"
printf ' <%s>' "$@" >> "$NIX_CALL_LOG"
printf '\n' >> "$NIX_CALL_LOG"
case "${1:-}" in
  eval)
    if [[ "$*" == *builtins.currentSystem* ]]; then
      printf 'x86_64-linux'
    else
      printf '["foundation-options","module-coverage","vm-users","vm-ssh"]'
    fi
    ;;
  build) ;;
  *) exit 2 ;;
esac
MOCK_NIX
chmod +x "$tmp/bin/nix"

assert "check batching helper exists" \
  "test -x '$REPO_ROOT/.github/scripts/build-checks.sh'"
assert "non-VM suite uses one Nix build invocation" \
  "NIX_BIN='$tmp/bin/nix' NIX_CALL_LOG='$tmp/non-vm.log' \
  bash '$REPO_ROOT/.github/scripts/build-checks.sh' non-vm"
assert "non-VM suite has exactly one build call" \
  "[[ \$(grep -c '^CALL <build>' '$tmp/non-vm.log' 2>/dev/null || true) -eq 1 ]]"
assert "non-VM suite includes ordinary checks" \
  "grep -Fq '<.#checks.x86_64-linux.foundation-options>' '$tmp/non-vm.log'"
assert "non-VM suite excludes VM checks" \
  "! grep -Fq '<.#checks.x86_64-linux.vm-users>' '$tmp/non-vm.log'"

assert "VM suite uses one Nix build invocation" \
  "NIX_BIN='$tmp/bin/nix' NIX_CALL_LOG='$tmp/vm.log' \
  bash '$REPO_ROOT/.github/scripts/build-checks.sh' vm"
assert "VM suite caps concurrent builds at two" \
  "grep -Fq '<--max-jobs> <2>' '$tmp/vm.log'"
assert "VM suite includes all five required checks" \
  "[[ \$(grep -o '<.#checks.x86_64-linux.vm-[^>]*>' '$tmp/vm.log' | sort -u | wc -l) -eq 5 ]]"

assert "PR validation runs workflow regression tests" \
  "grep -Fq 'bash tests/test-ci-workflows.sh' \
  '$REPO_ROOT/.github/workflows/pr-validation.yml'"
assert "PR validation omits duplicate standalone coverage run" \
  "! grep -Fq 'devenv tasks run check:coverage' \
  '$REPO_ROOT/.github/workflows/pr-validation.yml'"
assert "PR validation delegates checks to batching helper" \
  "grep -Fq 'bash .github/scripts/build-checks.sh non-vm' \
  '$REPO_ROOT/.github/workflows/pr-validation.yml'"
assert "VM workflow delegates checks to batching helper" \
  "grep -Fq 'bash .github/scripts/build-checks.sh vm' \
  '$REPO_ROOT/.github/workflows/pr-validation.yml'"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]] || exit 1
