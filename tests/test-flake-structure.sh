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
# (after moving them to targets/, flake.nix inline myConfig should be gone)
INLINE_MYCONFIG=$(grep -c "myConfig[[:space:]]*=" "$REPO_ROOT/flake.nix" 2>/dev/null || true)
INLINE_MYCONFIG="${INLINE_MYCONFIG:-0}"
assert "flake.nix has no inline myConfig assignments (found: $INLINE_MYCONFIG)" "[ '${INLINE_MYCONFIG}' -eq 0 ]"

# Each active machine should have a targets/ directory
for machine in wweaver zero MegamanX; do
  assert "targets/$machine/ exists" "test -d '$REPO_ROOT/targets/$machine'"
  assert "targets/$machine/default.nix exists" "test -f '$REPO_ROOT/targets/$machine/default.nix'"
done

# Each machine's target should contain myConfig
for machine in wweaver zero MegamanX; do
  assert "targets/$machine/default.nix contains myConfig" "grep -q 'myConfig' '$REPO_ROOT/targets/$machine/default.nix'"
done

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]] || exit 1
