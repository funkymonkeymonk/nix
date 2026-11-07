#!/usr/bin/env bash
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0
FAIL=0

assert() {
  local desc="$1" cmd="$2"
  if eval "$cmd" 2>/dev/null; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc"
    FAIL=$((FAIL + 1))
  fi
}

echo "=== Flake structure tests ==="

# flake.nix should not contain large inline myConfig blocks
# (machine modules are assembled by the catalog, not in flake.nix)
INLINE_MYCONFIG=$(grep -c "myConfig[[:space:]]*=" "$REPO_ROOT/flake.nix" 2>/dev/null || true)
INLINE_MYCONFIG="${INLINE_MYCONFIG:-0}"
assert "flake.nix has no inline myConfig assignments (found: $INLINE_MYCONFIG)" "[ '${INLINE_MYCONFIG}' -eq 0 ]"

# Each named machine configuration should have one canonical directory.
for machine in wweaver zero megamanx; do
  assert "machines/$machine/ exists" "test -d '$REPO_ROOT/machines/$machine'"
  assert "machines/$machine/default.nix exists" "test -f '$REPO_ROOT/machines/$machine/default.nix'"
done

# Each machine module should contain machine-specific settings.
for machine in wweaver zero megamanx; do
  assert "machines/$machine/default.nix contains myConfig" "grep -q 'myConfig' '$REPO_ROOT/machines/$machine/default.nix'"
done

# Legacy per-machine directories should be gone; targets remains for installer and hardware inputs.
for machine in wweaver zero megamanx; do
  assert "legacy machine directory targets/$machine/ is absent" "test ! -e '$REPO_ROOT/targets/$machine'"
  assert "legacy machine directory hosts/$machine/ is absent" "test ! -e '$REPO_ROOT/hosts/$machine'"
done

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]] || exit 1
