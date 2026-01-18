#!/usr/bin/env bash
# Test: Test skills directory creation with actual functionality verification
set -euo pipefail

echo "Testing skills directory creation..."

# Test directory for temporary home
TEST_HOME="/tmp/test-agent-skills-home"
TEST_SKILLS_DIR="$TEST_HOME/.config/opencode/skills"
TEST_SUPERPOWERS_DIR="$TEST_HOME/.config/opencode/superpowers/skills"

# Remove existing test directories
rm -rf "$TEST_HOME"

# Dynamically detect available configurations with platform preference
detect_available_config() {
  local flake_output
  local darwin_config
  local nixos_config
  
  # Try darwinConfigurations first (preferred for this test)
  darwin_config=$(grep -E 'darwinConfigurations\.' flake.nix | head -n1 | sed -E 's/.*\."(.+)".*/\1/' || true)
  
  # Try nixosConfigurations as fallback
  nixos_config=$(grep -E 'nixosConfigurations\.' flake.nix | head -n1 | sed -E 's/.*\."(.+)".*/\1/' || true)
  
  # Prefer darwin for this test (has better agent-skills support)
  if [[ -n "$darwin_config" ]]; then
    flake_output="$darwin_config"
  elif [[ -n "$nixos_config" ]]; then
    flake_output="$nixos_config"
  else
    echo "ERROR: No available configurations found in flake"
    exit 1
  fi
  
  echo "$flake_output"
}

# Detect configuration type (darwin or nixos)
detect_config_type() {
  local config="$1"
  if grep -q "darwinConfigurations.*\"$config\"" flake.nix; then
    echo "darwin"
  elif grep -q "nixosConfigurations.*\"$config\"" flake.nix; then
    echo "nixos"
  else
    # Default to darwin if pattern not found exactly
    echo "darwin"
  fi
}

AVAILABLE_CONFIG=$(detect_available_config)
CONFIG_TYPE=$(detect_config_type "$AVAILABLE_CONFIG")
echo "Found available configuration: $AVAILABLE_CONFIG (type: $CONFIG_TYPE)"

# RED: Test that verifies actual directory creation functionality
echo "Testing actual directory creation functionality..."

# Build configuration access based on type
if [[ "$CONFIG_TYPE" == "darwin" ]]; then
  CONFIG_ACCESS="(flake.darwinConfigurations.$AVAILABLE_CONFIG).config"
elif [[ "$CONFIG_TYPE" == "nixos" ]]; then
  CONFIG_ACCESS="(flake.nixosConfigurations.$AVAILABLE_CONFIG).config"
else
  echo "ERROR: Unknown configuration type: $CONFIG_TYPE"
  exit 1
fi

# Check if agent-skills module is available and would create directories
AGENT_SKILLS_ENABLED=$(nix eval --impure --raw --expr "
  let
    flake = builtins.getFlake (toString ./.);
    config = $CONFIG_ACCESS;
  in
  if config.myConfig.agent-skills.enable or false then \"true\" else \"false\"
")

if [[ "$AGENT_SKILLS_ENABLED" != "true" ]]; then
  echo "FAIL: agent-skills module not enabled in system configuration"
  echo "DEBUG: Checking system-level myConfig..."
  nix eval --impure --expr "
    let
      flake = builtins.getFlake (toString ./.);
      config = $CONFIG_ACCESS;
    in
    if config ? myConfig then builtins.attrNames config.myConfig else \"no myConfig\"
  " 2>/dev/null || echo "No myConfig found"
  exit 1
fi

# Now check if it's properly propagated to user config
USER_AGENT_SKILLS_ENABLED=$(nix eval --impure --raw --expr "
  let
    flake = builtins.getFlake (toString ./.);
    config = $CONFIG_ACCESS;
  in
  if config.home-manager.users.$AVAILABLE_CONFIG.myConfig.agent-skills.enable or false then \"true\" else \"false\"
")

if [[ "$USER_AGENT_SKILLS_ENABLED" != "true" ]]; then
  echo "FAIL: agent-skills not properly propagated to user configuration"
  exit 1
fi

SKILLS_PATH=$(nix eval --impure --raw --expr "
  let
    flake = builtins.getFlake (toString ./.);
    config = $CONFIG_ACCESS;
  in
  config.home-manager.users.$AVAILABLE_CONFIG.myConfig.agent-skills.skillsPath
")

SUPERPOWERS_PATH=$(nix eval --impure --raw --expr "
  let
    flake = builtins.getFlake (toString ./.);
    config = $CONFIG_ACCESS;
  in
  config.home-manager.users.$AVAILABLE_CONFIG.myConfig.agent-skills.superpowersPath
")

if [[ "$AGENT_SKILLS_ENABLED" != "true" ]]; then
  echo "FAIL: agent-skills module not enabled in system configuration"
  echo "DEBUG: Checking system-level myConfig..."
  nix eval --impure --expr '
    let
      flake = builtins.getFlake (toString ./.);
      config = (flake.darwinConfigurations.'$AVAILABLE_CONFIG').config;
    in
    if config ? myConfig then builtins.attrNames config.myConfig else "no myConfig"
  ' 2>/dev/null || echo "No myConfig found"
  exit 1
fi

# Now check if it's properly propagated to user config
USER_AGENT_SKILLS_ENABLED=$(nix eval --impure --raw --expr '
  let
    flake = builtins.getFlake (toString ./.);
    config = (flake.darwinConfigurations.'$AVAILABLE_CONFIG').config;
  in
  if config.home-manager.users.'$AVAILABLE_CONFIG'.myConfig.agent-skills.enable or false then "true" else "false"
')

if [[ "$USER_AGENT_SKILLS_ENABLED" != "true" ]]; then
  echo "FAIL: agent-skills not properly propagated to user configuration"
  exit 1
fi

SKILLS_PATH=$(nix eval --impure --raw --expr '
  let
    flake = builtins.getFlake (toString ./.);
    config = (flake.darwinConfigurations.'$AVAILABLE_CONFIG').config;
  in
  config.home-manager.users.'$AVAILABLE_CONFIG'.myConfig.agent-skills.skillsPath
')

SUPERPOWERS_PATH=$(nix eval --impure --raw --expr '
  let
    flake = builtins.getFlake (toString ./.);
    config = (flake.darwinConfigurations.'$AVAILABLE_CONFIG').config;
  in
  config.home-manager.users.'$AVAILABLE_CONFIG'.myConfig.agent-skills.superpowersPath
')

echo "Expected skills path: $SKILLS_PATH"
echo "Expected superpowers path: $SUPERPOWERS_PATH"

# Test if directories are configured to be created (this should fail initially)
if [[ "$SKILLS_PATH" == "/nonexistent" ]]; then
  echo "FAIL: agent-skills module not properly configured"
  exit 1
fi

# Check if home.file entries exist for directory creation
HAS_SKILLS_FILE=$(nix eval --impure --raw --expr "
  let
    flake = builtins.getFlake (toString ./.);
    config = $CONFIG_ACCESS;
    skillsPath = builtins.toString \"$SKILLS_PATH\";
  in
  if builtins.hasAttr \"\${skillsPath}/.keep\" config.home-manager.users.$AVAILABLE_CONFIG.home.file then \"true\" else \"false\"
")

HAS_SUPERPOWERS_FILE=$(nix eval --impure --raw --expr "
  let
    flake = builtins.getFlake (toString ./.);
    config = $CONFIG_ACCESS;
    superpowersPath = builtins.toString \"$SUPERPOWERS_PATH\";
  in
  if builtins.hasAttr \"\${superpowersPath}/.keep\" config.home-manager.users.$AVAILABLE_CONFIG.home.file then \"true\" else \"false\"
")

if [[ "$HAS_SKILLS_FILE" == "true" ]]; then
  echo "PASS: Skills directory creation configured"
else
  echo "FAIL: Skills directory creation not configured"
fi

if [[ "$HAS_SUPERPOWERS_FILE" == "true" ]]; then
  echo "PASS: Superpowers directory creation configured"
else
  echo "FAIL: Superpowers directory creation not configured"
fi

echo "RED test complete: Verifying actual directory configuration instead of just accessibility"