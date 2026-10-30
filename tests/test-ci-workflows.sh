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

# Test: Devenv CI tasks batch the non-VM and VM suites into one Nix build each.
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT
mkdir -p "$tmp/bin"
cat > "$tmp/bin/nix" <<'MOCK_NIX'
#!/usr/bin/env bash
set -euo pipefail
printf -v call ' <%s>' "$@"
printf 'CALL%s\n' "$call" >> "$NIX_CALL_LOG"
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

assert "Devenv CI task group runs both check suites" \
  "NIX_BIN='$tmp/bin/nix' NIX_CALL_LOG='$tmp/checks.log' \
  devenv tasks run ci:checks"
assert "non-VM task includes ordinary checks" \
  "grep -Fq '<.#checks.x86_64-linux.foundation-options>' '$tmp/checks.log'"
assert "non-VM task caps concurrent builds at two" \
  "grep -F '<.#checks.x86_64-linux.foundation-options>' '$tmp/checks.log' \\
  | grep -Fq '<--max-jobs> <2>'"
assert "non-VM task excludes VM checks" \
  "! grep -F '<.#checks.x86_64-linux.foundation-options>' '$tmp/checks.log' \
  | grep -Fq '<.#checks.x86_64-linux.vm-users>'"
assert "VM task caps concurrent builds at two" \
  "grep -Fq '<--max-jobs> <2>' '$tmp/checks.log'"
assert "VM task includes all five required checks" \
  "[[ \$(grep -o '<.#checks.x86_64-linux.vm-[^>]*>' '$tmp/checks.log' | sort -u | wc -l) -eq 5 ]]"
assert "check group issues one build per suite" \
  "[[ \$(grep -c '^CALL <build>' '$tmp/checks.log' 2>/dev/null || true) -eq 2 ]]"

assert "PR validation runs workflow regression tests" \
  "grep -Fq 'bash tests/test-ci-workflows.sh' \
  '$REPO_ROOT/.github/workflows/pr-validation.yml'"
assert "PR validation omits duplicate standalone coverage run" \
  "! grep -Fq 'devenv tasks run check:coverage' \
  '$REPO_ROOT/.github/workflows/pr-validation.yml'"
assert "PR validation runs the non-VM Devenv task" \
  "grep -Fq 'devenv tasks run ci:checks:non-vm' \
  '$REPO_ROOT/.github/workflows/pr-validation.yml'"
assert "VM workflow runs the VM Devenv task" \
  "grep -Fq 'devenv tasks run ci:checks:vm' \
  '$REPO_ROOT/.github/workflows/pr-validation.yml'"
assert "VM workflow installs the pinned Devenv CLI" \
  "[[ \$(grep -Fc 'nix profile add --accept-flake-config' \
  '$REPO_ROOT/.github/workflows/pr-validation.yml') -eq 3 ]]"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]] || exit 1
