#!/usr/bin/env bash
# Test: jj-autosync bash extraction from jj-autosync.nix
# Verifies that embedded scripts have been extracted to separate .sh files
set -uo pipefail

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

echo "=== jj-autosync bash extraction tests ==="
echo ""

# Test: no large inline bash heredocs remain in jj-autosync.nix
# "Large" = more than 5 lines of bash embedded directly in a Nix string (multi-line '' ... '')
INLINE_COUNT=$(grep -c "^  [a-zA-Z].*Content = ''\$" "$REPO_ROOT/modules/home-manager/jj-autosync.nix" 2>/dev/null; true)
assert "no large inline bash string assignments in jj-autosync.nix (found: ${INLINE_COUNT:-0})" \
    "[ '${INLINE_COUNT:-0}' -le 0 ]"

# Test: extracted .sh files exist alongside the module
assert "jj-autosync.sh exists in modules/home-manager/" \
    "[ -f '$REPO_ROOT/modules/home-manager/jj-autosync.sh' ]"

assert "jj-workspace-session.sh exists in modules/home-manager/" \
    "[ -f '$REPO_ROOT/modules/home-manager/jj-workspace-session.sh' ]"

assert "jj-fast-sync.sh exists in modules/home-manager/" \
    "[ -f '$REPO_ROOT/modules/home-manager/jj-fast-sync.sh' ]"

assert "jj-autosync-status.sh exists in modules/home-manager/" \
    "[ -f '$REPO_ROOT/modules/home-manager/jj-autosync-status.sh' ]"

assert "jj-autosync-lib.sh exists in modules/home-manager/" \
    "[ -f '$REPO_ROOT/modules/home-manager/jj-autosync-lib.sh' ]"

# Test: jj-autosync.nix uses builtins.readFile or writeShellApplication
assert "jj-autosync.nix references builtins.readFile or writeShellApplication" \
    "grep -qE '(builtins\.readFile|writeShellApplication)' '$REPO_ROOT/modules/home-manager/jj-autosync.nix'"

# Test: all .sh files have a shebang line
for sh_file in jj-autosync.sh jj-workspace-session.sh jj-fast-sync.sh jj-autosync-status.sh jj-autosync-lib.sh; do
    full_path="$REPO_ROOT/modules/home-manager/$sh_file"
    if [ -f "$full_path" ]; then
        assert "$sh_file starts with #!/usr/bin/env bash" \
            "head -1 '$full_path' | grep -q '#!/usr/bin/env bash'"
    fi
done

# Test: all .sh files pass shellcheck (if installed)
if command -v shellcheck &>/dev/null; then
    echo ""
    echo "  (shellcheck found - running script validation)"
    for f in "$REPO_ROOT/modules/home-manager/"jj-autosync*.sh; do
        if [ -f "$f" ]; then
            assert "shellcheck passes for $(basename "$f")" "shellcheck '$f'"
        fi
    done
else
    echo "  (shellcheck not installed - skipping shellcheck validation)"
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]] || exit 1
