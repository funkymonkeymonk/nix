#!/usr/bin/env bash
# Test: Agent skills auto-enable with opencode bundle
set -euo pipefail

echo "Testing agent-skills auto-enable with opencode..."

# Check if opencode bundle enables agent-skills
nix eval --impure --expr '
  let
    bundles = import ./bundles.nix { pkgs = import <nixpkgs> {}; lib = import <nixpkgs/lib>; };
    opencodeBundle = bundles.roles.llms.client.opensource;
  in
  opencodeBundle.enableAgentSkills or false
'

echo "Expected agent-skills to be auto-enabled by opencode"