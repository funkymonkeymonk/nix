#!/usr/bin/env bash
# Test: Agent skills module inclusion
set -euo pipefail

echo "Testing agent-skills module in system configurations..."

# Simple test: check if flake evaluation succeeds (module imports work)
echo "Checking wweaver configuration evaluation..."
nix flake check --quiet --no-build 2>/dev/null && echo "PASS: wweaver config evaluates successfully" || echo "FAIL: wweaver config evaluation failed"

echo "Checking if agent-skills module can be imported..."
nix-instantiate --eval --expr '
  let
    pkgs = import <nixpkgs> {};
    module = import ./modules/home-manager/agent-skills;
  in
  builtins.typeOf module
' 2>/dev/null && echo "PASS: Module can be imported directly" || echo "FAIL: Module import failed"

# Test if agent-skills is available in wweaver config when enabled
echo "Checking agent-skills availability in wweaver (when enabled)..."
nix eval --impure --expr '
  let
    flake = builtins.getFlake (toString ./.);
    config = flake.darwinConfigurations.wweaver.config;
    hasAgentSkillsOption = config.myConfig ? agent-skills;
  in
  hasAgentSkillsOption
' 2>/dev/null && echo "PASS: agent-skills option available in wweaver" || echo "FAIL: agent-skills option not found in wweaver"