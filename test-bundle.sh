#!/usr/bin/env bash
# Test: Agent skills bundle discovery
set -euo pipefail

echo "Testing agent-skills bundle availability..."

# Check if bundle is defined in bundles.nix
nix eval --impure --expr '
  let
    bundles = import ./bundles.nix { pkgs = import <nixpkgs> {}; lib = import <nixpkgs/lib>; };
  in
  bundles.roles.agent-skills
'

echo "PASS: Bundle found in bundles.nix"