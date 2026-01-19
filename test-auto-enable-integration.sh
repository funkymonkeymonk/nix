#!/usr/bin/env bash
# Test: Agent skills auto-enable integration test
set -euo pipefail

echo "Testing agent-skills auto-enable integration..."

# Test that wweaver_llm_client enables agent-skills
echo "Testing wweaver_llm_client enables agent-skills..."
nix eval --impure --expr '
  let
    flake = import ./flake.nix;
    pkgs = import <nixpkgs> {};
    lib = import <nixpkgs/lib>;
    
    # Simulate the mkBundleModule logic
    enabledRoles = ["wweaver_llm_client"];
    bundles = import ./bundles.nix {inherit pkgs lib;};
    
    # Check if any enabled bundle has enableAgentSkills
    hasAgentSkillsBundle = builtins.any (role: 
      (bundles.roles.${role} or {}).enableAgentSkills or false
    ) enabledRoles;
    
    # Also check nested llms client bundles
    hasLlmClientAgentSkills = builtins.any (role: 
      if role == "wweaver_llm_client" 
      then (bundles.roles.llms.client.opensource.enableAgentSkills or false)
      else if role == "wweaver_claude_client"
      then (bundles.roles.llms.client.claude.enableAgentSkills or false)
      else false
    ) enabledRoles;
    
    # Add agent-skills to enabled roles if auto-enabled
    rolesWithAgentSkills = 
      if hasAgentSkillsBundle || hasLlmClientAgentSkills
      then (lib.unique (enabledRoles ++ ["agent-skills"]))
      else enabledRoles;
    
    result = {
      inherit hasAgentSkillsBundle hasLlmClientAgentSkills rolesWithAgentSkills;
    };
  in
  result
'

# Test that wweaver_claude_client enables agent-skills
echo "Testing wweaver_claude_client enables agent-skills..."
nix eval --impure --expr '
  let
    pkgs = import <nixpkgs> {};
    lib = import <nixpkgs/lib>;
    
    # Simulate the mkBundleModule logic
    enabledRoles = ["wweaver_claude_client"];
    bundles = import ./bundles.nix {inherit pkgs lib;};
    
    # Check if any enabled bundle has enableAgentSkills
    hasAgentSkillsBundle = builtins.any (role: 
      (bundles.roles.${role} or {}).enableAgentSkills or false
    ) enabledRoles;
    
    # Also check nested llms client bundles
    hasLlmClientAgentSkills = builtins.any (role: 
      if role == "wweaver_llm_client" 
      then (bundles.roles.llms.client.opensource.enableAgentSkills or false)
      else if role == "wweaver_claude_client"
      then (bundles.roles.llms.client.claude.enableAgentSkills or false)
      else false
    ) enabledRoles;
    
    # Add agent-skills to enabled roles if auto-enabled
    rolesWithAgentSkills = 
      if hasAgentSkillsBundle || hasLlmClientAgentSkills
      then (lib.unique (enabledRoles ++ ["agent-skills"]))
      else enabledRoles;
    
    result = {
      inherit hasAgentSkillsBundle hasLlmClientAgentSkills rolesWithAgentSkills;
    };
  in
  result
'

# Test that regular roles don't enable agent-skills
echo "Testing regular roles don'\''t enable agent-skills..."
nix eval --impure --expr '
  let
    pkgs = import <nixpkgs> {};
    lib = import <nixpkgs/lib>;
    
    # Simulate the mkBundleModule logic
    enabledRoles = ["developer"];
    bundles = import ./bundles.nix {inherit pkgs lib;};
    
    # Check if any enabled bundle has enableAgentSkills
    hasAgentSkillsBundle = builtins.any (role: 
      (bundles.roles.${role} or {}).enableAgentSkills or false
    ) enabledRoles;
    
    # Also check nested llms client bundles
    hasLlmClientAgentSkills = builtins.any (role: 
      if role == "wweaver_llm_client" 
      then (bundles.roles.llms.client.opensource.enableAgentSkills or false)
      else if role == "wweaver_claude_client"
      then (bundles.roles.llms.client.claude.enableAgentSkills or false)
      else false
    ) enabledRoles;
    
    # Add agent-skills to enabled roles if auto-enabled
    rolesWithAgentSkills = 
      if hasAgentSkillsBundle || hasLlmClientAgentSkills
      then (lib.unique (enabledRoles ++ ["agent-skills"]))
      else enabledRoles;
    
    result = {
      inherit hasAgentSkillsBundle hasLlmClientAgentSkills rolesWithAgentSkills;
    };
  in
  result
'

echo "Integration tests completed!"