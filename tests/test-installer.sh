#!/usr/bin/env bash
# Tests for installer consolidation audit
# Verifies that both installer implementations exist and have clear purpose comments.
#
# Context: Two separate installers serve distinct purposes:
#   1. packages/installer/ — standalone `nix run` installer (plain bash, no gum)
#   2. targets/installer-iso/installer.nix — ISO-bundled installer (gum TUI, disko)
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0; FAIL=0

assert() {
  local desc="$1" cmd="$2"
  if eval "$cmd" 2>/dev/null; then echo "  PASS: $desc"; PASS=$((PASS+1))
  else echo "  FAIL: $desc"; FAIL=$((FAIL+1)); fi
}

echo "=== Installer consolidation tests ==="

# Both implementations must exist (they serve different purposes)
assert "packages/installer/default.nix exists" \
  "test -f '$REPO_ROOT/packages/installer/default.nix'"

assert "targets/installer-iso/installer.nix exists" \
  "test -f '$REPO_ROOT/targets/installer-iso/installer.nix'"

# Each file must have a purpose comment explaining why it exists separately
assert "packages/installer/default.nix has purpose comment" \
  "grep -q '# Purpose:' '$REPO_ROOT/packages/installer/default.nix'"

assert "targets/installer-iso/installer.nix has purpose comment" \
  "grep -q '# Purpose:' '$REPO_ROOT/targets/installer-iso/installer.nix'"

# The standalone package produces nixos-flake-installer binary name
assert "packages/installer produces nixos-flake-installer binary" \
  "grep -q 'writeScriptBin.*nixos-flake-installer' '$REPO_ROOT/packages/installer/default.nix'"

# The ISO installer produces nixos-installer-iso binary name
assert "targets/installer-iso/installer.nix produces nixos-installer-iso binary" \
  "grep -q 'writeScriptBin.*nixos-installer-iso' '$REPO_ROOT/targets/installer-iso/installer.nix'"

# flake.nix references both correctly
assert "flake.nix references packages/installer for standalone app" \
  "grep -q 'packages/installer' '$REPO_ROOT/flake.nix'"

assert "flake.nix references installer-iso NixOS config" \
  "grep -q 'installer-iso' '$REPO_ROOT/flake.nix'"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]] || exit 1
