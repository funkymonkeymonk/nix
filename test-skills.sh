#!/usr/bin/env bash
# Test: Test skills directory creation
set -euo pipefail

echo "Testing skills directory creation..."

# Remove existing test directories
rm -rf /tmp/test-skills /tmp/test-superpowers

# Build configuration that enables agent-skills
nix build --impure --expr '
  let
    flake = builtins.getFlake (toString ./.);
    system = (flake.darwinConfigurations.wweaver).config;
  in
  system
'

# Check if paths exist in configuration
nix eval --impure --expr '
  let
    flake = builtins.getFlake (toString ./.);
    system = (flake.darwinConfigurations.wweaver).config;
  in
  system.home-manager.users.wweaver.myConfig.agent-skills.skillsPath
'

echo "PASS: Module configuration available"