#!/usr/bin/env bash
# Test: Agent skills auto-enable with claude bundle
set -euo pipefail

echo "Testing agent-skills auto-enable with claude..."

# Check if claude bundle enables agent-skills
nix eval --impure --expr '
  let
    bundles = import ./bundles.nix { pkgs = import <nixpkgs> {}; lib = import <nixpkgs/lib>; };
    claudeBundle = bundles.roles.llms.client.claude;
  in
  claudeBundle.enableAgentSkills or false
'

echo "Expected agent-skills to be auto-enabled by claude"