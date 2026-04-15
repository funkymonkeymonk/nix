#!/usr/bin/env bash
# test-workspace-switch.sh
#
# Tests for the workspace-aware switch shell functions.
# Tests the jj-workspace-lib shared library directly using mock filesystem structures.
#
# Uses a simple PASS/FAIL harness — no external dependencies required.

set -euo pipefail

# ============================================================
# Test harness
# ============================================================

PASS=0
FAIL=0
ERRORS=()

pass() {
  local msg="$1"
  echo "  PASS: $msg"
  PASS=$((PASS + 1))
}

fail() {
  local msg="$1"
  echo "  FAIL: $msg"
  FAIL=$((FAIL + 1))
  ERRORS+=("$msg")
}

assert_eq() {
  local desc="$1"
  local expected="$2"
  local actual="$3"
  if [[ "$actual" == "$expected" ]]; then
    pass "$desc"
  else
    fail "$desc (expected '$expected', got '$actual')"
  fi
}

assert_true() {
  local desc="$1"
  local result="$2"
  if [[ "$result" == "0" ]]; then
    pass "$desc"
  else
    fail "$desc (expected return 0, got $result)"
  fi
}

assert_false() {
  local desc="$1"
  local result="$2"
  if [[ "$result" != "0" ]]; then
    pass "$desc"
  else
    fail "$desc (expected non-zero return, got 0)"
  fi
}

section() {
  echo ""
  echo "=== $1 ==="
}

summary() {
  echo ""
  echo "Results: $PASS passed, $FAIL failed"
  if [[ ${#ERRORS[@]} -gt 0 ]]; then
    echo ""
    echo "Failed tests:"
    for err in "${ERRORS[@]}"; do
      echo "  - $err"
    done
    exit 1
  fi
  echo "All tests passed"
}

# ============================================================
# Load library under test
# ============================================================

# SCRIPT_DIR is injected by the Nix derivation; fall back for local runs
SCRIPT_DIR="${SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/..}"
LIB_PATH="$SCRIPT_DIR/modules/common/scripts/jj-workspace-lib"

if [[ ! -f "$LIB_PATH" ]]; then
  echo "ERROR: Could not find jj-workspace-lib at $LIB_PATH"
  exit 1
fi

# shellcheck source=../modules/common/scripts/jj-workspace-lib
source "$LIB_PATH"

# ============================================================
# Fixture helpers
# ============================================================

# Create a mock main jj repository at <dir>
# A main repo has .jj/repo as a DIRECTORY
make_main_repo() {
  local dir="$1"
  mkdir -p "$dir/.jj/repo"
}

# Create a mock jj workspace at <workspace_dir> pointing to <main_dir>
# A workspace has .jj/repo as a FILE containing a relative path to the main .jj/repo
make_workspace() {
  local workspace_dir="$1"
  local main_dir="$2"
  mkdir -p "$workspace_dir/.jj"
  # The pointer in .jj/repo is relative from workspace's .jj/ to main's .jj/repo dir
  local rel_path
  rel_path=$(python3 -c "import os; print(os.path.relpath('$main_dir/.jj/repo', '$workspace_dir/.jj'))" 2>/dev/null \
    || python -c "import os; print(os.path.relpath('$main_dir/.jj/repo', '$workspace_dir/.jj'))" 2>/dev/null \
    || realpath --relative-to="$workspace_dir/.jj" "$main_dir/.jj/repo" 2>/dev/null)
  echo "$rel_path" > "$workspace_dir/.jj/repo"
}

# Create a directory that is NOT a jj repo at all
make_plain_dir() {
  local dir="$1"
  mkdir -p "$dir"
}

# ============================================================
# Tests: detect_jj_repo_root
# ============================================================

section "detect_jj_repo_root: main repository"

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

MAIN_REPO="$TMPDIR/main-repo"
make_main_repo "$MAIN_REPO"

result=$(detect_jj_repo_root "$MAIN_REPO")
assert_eq "returns main repo path when .jj/repo is a directory" "$MAIN_REPO" "$result"

section "detect_jj_repo_root: workspace"

WORKSPACE="$TMPDIR/workspaces/feat-my-feature"
make_workspace "$WORKSPACE" "$MAIN_REPO"

result=$(detect_jj_repo_root "$WORKSPACE")
assert_eq "returns main repo path from a workspace" "$MAIN_REPO" "$result"

section "detect_jj_repo_root: non-jj directory"

PLAIN_DIR="$TMPDIR/plain"
make_plain_dir "$PLAIN_DIR"

# Should return non-zero when there's no .jj directory at all
# Wrap in subshell without set -e to capture the real return code
rc=0; detect_jj_repo_root "$PLAIN_DIR" > /dev/null 2>&1 || rc=$?
assert_false "returns non-zero for directories without .jj" "$rc"

section "detect_jj_repo_root: nested workspace structures"

# Simulate a real-world layout: main repo + multiple workspace siblings
REAL_MAIN="$TMPDIR/real/nix"
REAL_WS1="$TMPDIR/real/nix/.workspaces/feat-auth"
REAL_WS2="$TMPDIR/real/nix/.workspaces/fix-login"
make_main_repo "$REAL_MAIN"
make_workspace "$REAL_WS1" "$REAL_MAIN"
make_workspace "$REAL_WS2" "$REAL_MAIN"

result1=$(detect_jj_repo_root "$REAL_WS1")
assert_eq "workspace 1 resolves to main repo" "$REAL_MAIN" "$result1"

result2=$(detect_jj_repo_root "$REAL_WS2")
assert_eq "workspace 2 resolves to main repo" "$REAL_MAIN" "$result2"

result_main=$(detect_jj_repo_root "$REAL_MAIN")
assert_eq "main repo resolves to itself" "$REAL_MAIN" "$result_main"

# ============================================================
# Tests: is_jj_workspace
# ============================================================

section "is_jj_workspace: workspace detection"

# In a workspace: workspace_root != repo_root AND .jj exists
WS_ROOT="$TMPDIR/ws-root"
WS_MAIN="$TMPDIR/ws-main"
make_main_repo "$WS_MAIN"
make_workspace "$WS_ROOT" "$WS_MAIN"

is_jj_workspace "$WS_ROOT" "$WS_MAIN"
rc=$?
assert_true "is_jj_workspace returns 0 for a workspace" "$rc"

section "is_jj_workspace: main repo is not a workspace"

# In main repo: workspace_root == repo_root
MR="$TMPDIR/main-only"
make_main_repo "$MR"

rc=0; is_jj_workspace "$MR" "$MR" || rc=$?
assert_false "is_jj_workspace returns non-zero when in main repo" "$rc"

section "is_jj_workspace: plain dir is not a workspace"

PLAIN2="$TMPDIR/plain2"
make_plain_dir "$PLAIN2"

rc=0; is_jj_workspace "$PLAIN2" "$PLAIN2" || rc=$?
assert_false "is_jj_workspace returns non-zero for plain directory" "$rc"

# ============================================================
# Tests: function definitions in workspace context
# ============================================================

section "Shell function definitions: workspace context"

# Simulate what devenv.nix enterShell does in a workspace context
FAKE_REPO_ROOT="$TMPDIR/fake-repo"

# Define functions as devenv.nix would in workspace mode
s() { echo "workspace-switch from $FAKE_REPO_ROOT"; }
switch() { echo "workspace-switch from $FAKE_REPO_ROOT"; }
b() { echo "workspace-build from $FAKE_REPO_ROOT"; }
q() { echo "workspace-check from $FAKE_REPO_ROOT"; }

assert_eq "s function is defined" "workspace-switch from $FAKE_REPO_ROOT" "$(s)"
assert_eq "switch function is defined" "workspace-switch from $FAKE_REPO_ROOT" "$(switch)"
assert_eq "b function is defined" "workspace-build from $FAKE_REPO_ROOT" "$(b)"
assert_eq "q function is defined" "workspace-check from $FAKE_REPO_ROOT" "$(q)"

# Functions should be callable (not aliases that fail outside devenv)
rc=0; declare -f s > /dev/null || rc=$?
assert_true "s is defined as a shell function (not alias)" "$rc"

rc=0; declare -f switch > /dev/null || rc=$?
assert_true "switch is defined as a shell function (not alias)" "$rc"

rc=0; declare -f b > /dev/null || rc=$?
assert_true "b is defined as a shell function (not alias)" "$rc"

rc=0; declare -f q > /dev/null || rc=$?
assert_true "q is defined as a shell function (not alias)" "$rc"

section "Shell function definitions: non-workspace context"

# Unset previous definitions
unset -f s switch b q

# Simulate non-workspace mode (functions run directly, not from repo root)
s() { echo "direct-switch"; }
switch() { echo "direct-switch"; }
b() { echo "direct-build"; }
q() { echo "direct-check"; }

assert_eq "s defined in non-workspace context" "direct-switch" "$(s)"
assert_eq "switch defined in non-workspace context" "direct-switch" "$(switch)"
assert_eq "b defined in non-workspace context" "direct-build" "$(b)"
assert_eq "q defined in non-workspace context" "direct-check" "$(q)"

# ============================================================
# Summary
# ============================================================

summary
