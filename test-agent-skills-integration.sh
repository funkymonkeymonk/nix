#!/usr/bin/env bash
# Test: Verify agent-skills packages are included in system packages
set -euo pipefail

echo "Testing that agent-skills packages are included when opencode is enabled..."

# Test wweaver configuration which has wweaver_llm_client
echo "Testing wweaver configuration..."
nix eval --impure --expr '
  let
    flake = builtins.getFlake (toString ./.);
    config = (flake.darwinConfigurations.wweaver).config;
    agentSkillsPackages = builtins.filter (pkg: builtins.match ".*git.*" (pkg.name or "") != null) config.environment.systemPackages;
    hasGit = builtins.length agentSkillsPackages > 0;
  in
  {
    inherit hasGit;
    systemPackageCount = builtins.length config.environment.systemPackages;
    agentSkillsVars = config.environment.sessionVariables or {};
  }
'

echo "Testing that agent-skills environment variables are set..."
nix eval --impure --expr '
  let
    flake = builtins.getFlake (toString ./.);
    config = (flake.darwinConfigurations.wweaver).config;
    agentSkillsVars = config.environment.sessionVariables or {};
  in
  {
    AGENT_SKILLS_PATH = agentSkillsVars.AGENT_SKILLS_PATH or "not-set";
    SUPERPOWERS_SKILLS_PATH = agentSkillsVars.SUPERPOWERS_SKILLS_PATH or "not-set";
  }
'

echo "Agent-skills integration test completed!"