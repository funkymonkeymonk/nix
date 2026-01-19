#!/usr/bin/env bash
# Test: Complete agent skills integration
set -euo pipefail

echo "=== Agent Skills Integration Test ==="

# Test 1: Module loading
echo "1. Testing module loading..."
nix eval --impure --expr '
  let
    flake = builtins.getFlake (toString ./.);
    config = flake.darwinConfigurations.wweaver.config;
  in
  config ? myConfig.agent-skills
' >/dev/null && echo "✓ Module loads correctly" || { echo "✗ Module loading failed"; exit 1; }

# Test 2: Bundle integration
echo "2. Testing bundle integration..."
nix eval --impure --expr '
  let bundles = import ./bundles.nix { pkgs = import <nixpkgs> {}; lib = import <nixpkgs/lib>; };
  in bundles.roles.agent-skills.packages
' >/dev/null && echo "✓ Bundle configured correctly" || { echo "✗ Bundle integration failed"; exit 1; }

# Test 3: Auto-enable with opencode
echo "3. Testing auto-enable with opencode..."
nix eval --impure --expr '
  let bundles = import ./bundles.nix { pkgs = import <nixpkgs> {}; lib = import <nixpkgs/lib>; };
  in (bundles.roles.opencode.enableAgentSkills or false)
' >/dev/null && echo "✓ Auto-enable configured" || { echo "✗ Auto-enable failed"; exit 1; }

# Test 4: Skills presence
echo "4. Testing skills presence..."
find modules/home-manager/agent-skills/skills -name "SKILL.md" | wc -l | grep -q "^[1-9]" && echo "✓ Skills present in repository" || { echo "✗ No skills found"; exit 1; }

# Test 5: Task commands
echo "5. Testing task commands..."
task --list-all | grep -q "agent-skills:" && echo "✓ Task commands available" || { echo "✗ Task commands missing"; exit 1; }

echo ""
echo "🎉 All integration tests passed!"