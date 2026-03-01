# Agent Skills Management Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Create a Nix-based agent skills management system that automatically installs skills with opencode/claude bundles and provides clean update mechanism from upstream superpowers.

**Architecture:** Modular Nix system with agent-skills bundle, home-manager integration for file placement, and git-based update mechanism tracking upstream superpowers repository.

**Tech Stack:** Nix, home-manager, Taskfile.dev, Agent Skills specification

### Task 1: Create Core Module Structure

**Files:**
- Create: `modules/agent-skills/default.nix`
- Create: `modules/agent-skills/skills.nix` 
- Create: `modules/agent-skills/updates.nix`
- Create: `modules/agent-skills/.upstream-version`

**Step 1: Write the failing test for module loading**

```nix
# Test: modules/agent-skills/test.nix
{ lib, ... }:
{
  # Basic module structure test
  config = {
    assertions = [
      {
        assertion = lib.hasAttr "agent-skills" config.modules;
        message = "agent-skills module should be available";
      }
    ];
  };
}
```

**Step 2: Run test to verify it fails**

Run: `nix eval --impure --expr 'let flake = builtins.getFlake (toString ./.); in flake.darwinConfigurations.wweaver.config.modules.agent-skills' 2>&1 | grep "attribute.*missing"`
Expected: FAIL with module not found error

**Step 3: Write minimal module implementation**

```nix
# Create: modules/agent-skills/default.nix
{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.myConfig.agent-skills;
in
{
  options.myConfig.agent-skills = {
    enable = mkEnableOption "Agent skills management";
    skillsPath = mkOption {
      type = types.str;
      default = "${config.home.homeDirectory}/.config/opencode/skills";
      description = "Path where skills should be installed";
    };
    superpowersPath = mkOption {
      type = types.str;
      default = "${config.home.homeDirectory}/.config/opencode/superpowers/skills";
      description = "Path where superpowers skills should be installed";
    };
  };

  config = mkIf cfg.enable {
    # Module implementation will be added in next task
  };
}
```

**Step 4: Run test to verify it passes**

Run: `nix eval --impure --expr 'let flake = builtins.getFlake (toString ./.); in (flake.darwinConfigurations.wweaver.config.modules.agent-skills.enable true)'`
Expected: PASS (no errors)

**Step 5: Commit**

```bash
git add modules/agent-skills/default.nix
git commit -m "feat: add agent-skills module structure"
```

### Task 2: Implement Skills Management Logic

**Files:**
- Modify: `modules/agent-skills/default.nix`
- Create: `modules/agent-skills/skills.nix`

**Step 1: Write the failing test for skills installation**

```bash
# Test script for skills directory creation
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
  system.myConfig.agent-skills.enable true
'

# Check if paths exist in configuration
nix eval --impure --expr '
  let
    flake = builtins.getFlake (toString ./.);
    system = (flake.darwinConfigurations.wweaver).config;
  in
  system.myConfig.agent-skills.skillsPath
'

echo "PASS: Module configuration available"
```

**Step 2: Run test to verify it fails**

Run: `chmod +x test-skills.sh && ./test-skills.sh`
Expected: FAIL with paths not configured correctly

**Step 3: Write skills management implementation**

```nix
# Create: modules/agent-skills/skills.nix
{ lib, pkgs, config, ... }:

let
  cfg = config.myConfig.agent-skills;
  
  # Function to create skill directory structure
  mkSkillDir = path: content: pkgs.runCommand "skill-dir" {} ''
    mkdir -p $out
    cp -r ${content}/* $out/
  '';
  
  # Skills from repository
  repoSkills = builtins.attrValues (builtins.readDir ../agent-skills/skills);
  
in
{
  config = lib.mkIf cfg.enable {
    # Ensure directories exist and have proper permissions
    home.file.".config/opencode/skills/.keep" = {
      text = "";
      onChange = "mkdir -p ${cfg.skillsPath}";
    };
    
    home.file.".config/opencode/superpowers/skills/.keep" = {
      text = "";
      onChange = "mkdir -p ${cfg.superpowersPath}";
    };

    # Install skills from repository
    home.file = lib.listToAttrs (
      map
        (skillName: {
          name = ".config/opencode/skills/${skillName}";
          value = {
            source = ../agent-skills/skills/${skillName};
            recursive = true;
          };
        })
        repoSkills
    );
    
    # Also install to superpowers path for compatibility
    home.file = lib.listToAttrs (
      map
        (skillName: {
          name = ".config/opencode/superpowers/skills/${skillName}";
          value = {
            source = ../agent-skills/skills/${skillName};
            recursive = true;
          };
        })
        repoSkills
    );
  };
}
```

**Step 4: Modify default.nix to include skills.nix**

```nix
# Modify: modules/agent-skills/default.nix (add this in config section)
config = mkIf cfg.enable {
  imports = [ ./skills.nix ];
  
  # Additional configuration will be added
};
```

**Step 5: Run test to verify it passes**

Run: `nix build --impure --expr 'let flake = builtins.getFlake (toString ./.); in (flake.darwinConfigurations.wweaver).config.myConfig.agent-skills.enable true'`
Expected: PASS (successful build)

**Step 6: Commit**

```bash
git add modules/agent-skills/skills.nix modules/agent-skills/default.nix
git commit -m "feat: implement skills installation logic"
```

### Task 3: Create Agent Skills Bundle

**Files:**
- Create: `bundles/roles/agent-skills.nix`
- Modify: `bundles.nix` (to include new bundle)

**Step 1: Write the failing test for bundle discovery**

```bash
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
```

**Step 2: Run test to verify it fails**

Run: `./test-bundle.sh`
Expected: FAIL with "attribute 'agent-skills' missing"

**Step 3: Create agent-skills bundle**

```nix
# Create: bundles/roles/agent-skills.nix
{ pkgs, lib, ... }:

let
  # Tools needed for agent skills management
  tools = with pkgs; [
    git  # For updates from upstream
    jq   # For JSON processing in update scripts
  ];
  
in
{
  packages = tools;
  
  config = {
    # Environment variables for skills paths
    environment.sessionVariables = {
      AGENT_SKILLS_PATH = "${config.home.homeDirectory}/.config/opencode/skills";
      SUPERPOWERS_SKILLS_PATH = "${config.home.homeDirectory}/.config/opencode/superpowers/skills";
    };
    
    # Shell aliases for skills management
    shellAliases = {
      skills-status = "ls -la $AGENT_SKILLS_PATH $SUPERPOWERS_SKILLS_PATH";
      skills-update = "task agent-skills:update";
      skills-list = "find $AGENT_SKILLS_PATH -name 'SKILL.md' -exec basename {} \\; | sort";
    };
  };
}
```

**Step 4: Update bundles.nix to include agent-skills**

```nix
# Modify: bundles.nix (in roles section)
roles = {
  # ... existing roles ...
  
  agent-skills = {
    packages = with pkgs; [
      git
      jq
    ];
    
    config = {
      environment.sessionVariables = {
        AGENT_SKILLS_PATH = "${config.home.homeDirectory}/.config/opencode/skills";
        SUPERPOWERS_SKILLS_PATH = "${config.home.homeDirectory}/.config/opencode/superpowers/skills";
      };
    };
  };
};
```

**Step 5: Run test to verify it passes**

Run: `nix eval --impure --expr 'let bundles = import ./bundles.nix { pkgs = import <nixpkgs> {}; lib = import <nixpkgs/lib>; }; in bundles.roles.agent-skills.packages'`
Expected: PASS (returns list with git and jq)

**Step 6: Commit**

```bash
git add bundles/roles/agent-skills.nix bundles.nix
git commit -m "feat: add agent-skills bundle"
```

### Task 4: Implement Auto-Enable Logic

**Files:**
- Modify: `bundles.nix` (opencode bundle)
- Modify: `bundles.nix` (claude bundle)
- Modify: `flake.nix` (to include agent-skills module)

**Step 1: Write the failing test for auto-enable**

```bash
#!/usr/bin/env bash
# Test: Agent skills auto-enable with opencode bundle
set -euo pipefail

echo "Testing agent-skills auto-enable with opencode..."

# Check if opencode bundle enables agent-skills
nix eval --impure --expr '
  let
    bundles = import ./bundles.nix { pkgs = import <nixpkgs> {}; lib = import <nixpkgs/lib>; };
    opencodeBundle = bundles.roles.opencode;
  in
  opencodeBundle.enableAgentSkills or false
'

echo "Expected agent-skills to be auto-enabled by opencode"
```

**Step 2: Run test to verify it fails**

Run: `./test-auto-enable.sh`
Expected: FAIL with false or missing attribute

**Step 3: Modify opencode bundle to auto-enable agent-skills**

```nix
# Modify: bundles.nix (in opencode bundle)
opencode = {
  packages = with pkgs; [
    (if pkgs ? unstable then pkgs.unstable.opencode else opencode)
  ];
  
  # Auto-enable agent-skills
  enableAgentSkills = true;
  
  config = {
    # existing opencode config...
  };
};
```

**Step 4: Modify claude bundle to auto-enable agent-skills**

```nix
# Modify: bundles.nix (in claude bundle)  
claude = {
  packages = with pkgs; [
    claude-code
  ];
  
  # Auto-enable agent-skills
  enableAgentSkills = true;
  
  config = {
    # existing claude config...
  };
};
```

**Step 5: Update bundle module logic to handle auto-enable**

```nix
# Modify: flake.nix (in mkBundleModule function, around line 53)
mkBundleModule = system: enabledRoles: {
  pkgs,
  lib,
  ...
}: {
  config = let
    bundles = import ./bundles.nix {inherit pkgs lib;};
    
    # Check if any enabled bundle has enableAgentSkills
    hasAgentSkillsBundle = builtins.any (role: 
      (bundles.roles.${role} or {}).enableAgentSkills or false
    ) enabledRoles;
    
    # Add agent-skills to enabled roles if auto-enabled
    rolesWithAgentSkills = 
      if hasAgentSkillsBundle 
      then (lib.unique (enabledRoles ++ ["agent-skills"]))
      else enabledRoles;

    # ... rest of existing bundle logic continues with rolesWithAgentSkills
```

**Step 6: Run test to verify it passes**

Run: `./test-auto-enable.sh`
Expected: PASS (returns true)

**Step 7: Commit**

```bash
git add bundles.nix flake.nix
git commit -m "feat: implement agent-skills auto-enable with opencode/claude"
```

### Task 5: Create Update Mechanism

**Files:**
- Create: `modules/agent-skills/updates.nix`
- Create: `modules/agent-skills/.upstream-version`
- Modify: `Taskfile.yml`

**Step 1: Write the failing test for update mechanism**

```bash
#!/usr/bin/env bash
# Test: Agent skills update mechanism
set -euo pipefail

echo "Testing update mechanism..."

# Check if update command exists
task --list-all | grep "agent-skells:" || echo "No agent-skills tasks found"

# Check if upstream version tracking file exists
test -f modules/agent-skills/.upstream-version || echo "No version tracking file"
```

**Step 2: Run test to verify it fails**

Run: `./test-update.sh`
Expected: FAIL with no agent-skills tasks or version file

**Step 3: Create update mechanism implementation**

```nix
# Create: modules/agent-skills/updates.nix
{ config, lib, pkgs, ... }:

let
  cfg = config.myConfig.agent-skills;
  
  # Upstream repository information
  upstreamRepo = "https://github.com/obra/superpowers.git";
  upstreamBranch = "main";
  
  # Version tracking file
  versionFile = builtins.toString ../agent-skills/.upstream-version;
  
in
{
  config = lib.mkIf cfg.enable {
    # Create update script
    home.packages = [
      (pkgs.writeShellScriptBin "update-agent-skills" ''
        set -euo pipefail
        
        echo "Updating agent skills from upstream..."
        
        # Read current version
        if [[ -f "${versionFile}" ]]; then
          current_version=$(cat "${versionFile}")
        else
          current_version="none"
        fi
        
        echo "Current version: $current_version"
        
        # Clone upstream to temporary directory
        temp_dir=$(mktemp -d)
        trap "rm -rf $temp_dir" EXIT
        
        git clone --depth 1 "${upstreamRepo}" "$temp_dir"
        
        # Get latest commit hash
        latest_version=$(cd "$temp_dir" && git rev-parse HEAD)
        
        echo "Latest version: $latest_version"
        
        if [[ "$current_version" = "$latest_version" ]]; then
          echo "Already up to date"
          exit 0
        fi
        
        # Update skills
        echo "Updating skills from $temp_dir/skills to ${config.home.homeDirectory}/.config/opencode/skills"
        mkdir -p "${config.home.homeDirectory}/.config/opencode/skills"
        mkdir -p "${config.home.homeDirectory}/.config/opencode/superpowers/skills"
        
        # Copy new skills, preserving custom ones
        if [[ -d "$temp_dir/skills" ]]; then
          rsync -av --delete "$temp_dir/skills/" "${config.home.homeDirectory}/.config/opencode/skills/"
          rsync -av --delete "$temp_dir/skills/" "${config.home.homeDirectory}/.config/opencode/superpowers/skills/"
        fi
        
        # Update version tracking
        echo "$latest_version" > "${versionFile}"
        
        echo "Skills updated successfully!"
        echo "Version: $latest_version"
      '')
    ];
  };
}
```

**Step 4: Create version tracking file**

```bash
# Create: modules/agent-skills/.upstream-version
# Initialize as empty (will be set on first update)
```

**Step 5: Add Taskfile commands**

```yaml
# Modify: Taskfile.yml (add these tasks)
  agent-skills:status:
    desc: Check agent skills status
    cmds:
      - echo "=== Agent Skills Status ==="
      - echo "Skills directory: $HOME/.config/opencode/skills"
      - echo "Superpowers directory: $HOME/.config/opencode/superpowers/skills"
      - echo "Available skills:"
      - find "$HOME/.config/opencode/skills" -name "SKILL.md" 2>/dev/null | wc -l | xargs -I {} echo "  {} skills in main directory"
      - find "$HOME/.config/opencode/superpowers/skills" -name "SKILL.md" 2>/dev/null | wc -l | xargs -I {} echo "  {} skills in superpowers directory"
      - echo ""
      - echo "Upstream version:"
      - cat modules/agent-skills/.upstream-version 2>/dev/null || echo "  Not tracked"

  agent-skills:update:
    desc: Update agent skills from upstream superpowers
    cmds:
      - echo "Updating agent skills from upstream..."
      - update-agent-skills
    silent: true

  agent-skills:validate:
    desc: Validate skills against Agent Skills specification
    cmds:
      - echo "Validating skills format..."
      - find "$HOME/.config/opencode/skills" -name "SKILL.md" -exec echo "Checking: {}" \; -exec head -10 {} \;
      - echo "Validation complete"
```

**Step 6: Update default.nix to include updates.nix**

```nix
# Modify: modules/agent-skills/default.nix (add to imports)
config = mkIf cfg.enable {
  imports = [ ./skills.nix ./updates.nix ];
  
  # Additional configuration
};
```

**Step 7: Run test to verify it passes**

Run: `task agent-skills:status`
Expected: PASS (shows status information)

**Step 8: Commit**

```bash
git add modules/agent-skills/updates.nix modules/agent-skills/.upstream-version Taskfile.yml modules/agent-skills/default.nix
git commit -m "feat: add skills update mechanism"
```

### Task 6: Add Module to System Configurations

**Files:**
- Modify: `flake.nix` (all system configurations)

**Step 1: Write the failing test for module inclusion**

```bash
#!/usr/bin/env bash
# Test: Agent skills module inclusion
set -euo pipefail

echo "Testing agent-skills module in system configurations..."

# Test if module is available in wweaver configuration
nix eval --impure --expr '
  let
    flake = builtins.getFlake (toString ./.);
    config = flake.darwinConfigurations.wweaver.config;
  in
  config ? myConfig.agent-skills
' 2>/dev/null && echo "PASS: Module available in wweaver" || echo "FAIL: Module not found in wweaver"
```

**Step 2: Run test to verify it fails**

Run: `./test-module.sh`
Expected: FAIL with module not found

**Step 3: Add agent-skills module to all configurations**

```nix
# Modify: flake.nix (add agent-skills import to each configuration)
# For darwinConfigurations.wweaver (around line 127):
        ./modules/common/options.nix
        ./modules/common/users.nix
        ./modules/home-manager
        ./modules/agent-skills  # Add this line
        ./os/darwin.nix

# For darwinConfigurations.MegamanX (around line 174):
        ./modules/common/options.nix
        ./modules/common/users.nix
        ./modules/home-manager
        ./modules/agent-skills  # Add this line
        ./os/darwin.nix

# For nixosConfigurations.drlight (around line 55):
        ./modules/common/options.nix
        ./modules/common/users.nix
        ./modules/common/shell.nix
        ./modules/home-manager
        ./modules/agent-skills  # Add this line
        ./modules/nixos/hardware.nix

# For nixosConfigurations.zero (around line 90):
        ./modules/common/options.nix
        ./modules/common/users.nix
        ./modules/common/shell.nix
        ./modules/home-manager
        ./modules/agent-skills  # Add this line
        ./os/nixos.nix
```

**Step 4: Run test to verify it passes**

Run: `./test-module.sh`
Expected: PASS (module found in configuration)

**Step 5: Commit**

```bash
git add flake.nix
git commit -m "feat: add agent-skills module to all system configurations"
```

### Task 7: Migrate Existing Superpowers Skills

**Files:**
- Create: `modules/agent-skills/skills/` (with all skill directories)
- Copy skills from `~/.config/opencode/superpowers/skills/`

**Step 1: Write the failing test for skills migration**

```bash
#!/usr/bin/env bash
# Test: Superpowers skills migration
set -euo pipefail

echo "Testing skills migration..."

# Check if skills directory exists
test -d modules/agent-skills/skills && echo "Skills directory exists" || echo "FAIL: Skills directory missing"

# Check if at least one skill is present
find modules/agent-skills/skills -name "SKILL.md" | head -1 && echo "Skills present" || echo "FAIL: No skills found"
```

**Step 2: Run test to verify it fails**

Run: `./test-migration.sh`
Expected: FAIL with no skills directory or skills

**Step 3: Create skills directory structure**

```bash
# Create the skills directory
mkdir -p modules/agent-skills/skills
```

**Step 4: Copy existing skills**

```bash
# Copy all skill directories from superpowers
cp -r ~/.config/opencode/superpowers/skills/* modules/agent-skills/skills/

# Verify the copy
ls -la modules/agent-skills/skills/
```

**Step 5: Update skill files to follow Agent Skills specification**

```bash
# Ensure all SKILL.md files have proper frontmatter
for skill_dir in modules/agent-skills/skills/*/; do
  if [[ -f "$skill_dir/SKILL.md" ]]; then
    # Check if frontmatter exists
    if ! head -5 "$skill_dir/SKILL.md" | grep -q "^---"; then
      echo "WARNING: $skill_dir/SKILL.md missing frontmatter"
    fi
  fi
done
```

**Step 6: Run test to verify it passes**

Run: `./test-migration.sh`
Expected: PASS (skills directory exists and contains skills)

**Step 7: Commit**

```bash
git add modules/agent-skills/skills/
git commit -m "feat: migrate superpowers skills to repository"
```

### Task 8: Final Integration Testing

**Files:**
- Create: `test-agent-skills.sh` (comprehensive test)

**Step 1: Write comprehensive integration test**

```bash
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
echo "3. Testing auto-enable..."
nix eval --impure --expr '
  let bundles = import ./bundles.nix { pkgs = import <nixpkgs> {}; lib = import <nixpkgs/lib>; };
  in (bundles.roles.opencode.enableAgentSkills or false)
' >/dev/null && echo "✓ Auto-enable configured" || { echo "✗ Auto-enable failed"; exit 1; }

# Test 4: Skills presence
echo "4. Testing skills presence..."
find modules/agent-skills/skills -name "SKILL.md" | wc -l | grep -q "^[1-9]" && echo "✓ Skills present in repository" || { echo "✗ No skills found"; exit 1; }

# Test 5: Task commands
echo "5. Testing task commands..."
task --list-all | grep -q "agent-skills:" && echo "✓ Task commands available" || { echo "✗ Task commands missing"; exit 1; }

echo ""
echo "🎉 All integration tests passed!"
```

**Step 2: Run comprehensive test**

Run: `chmod +x test-agent-skills.sh && ./test-agent-skills.sh`
Expected: PASS (all tests pass)

**Step 3: Test actual system build**

Run: `task build:darwin:wweaver`
Expected: PASS (successful build with agent-skills enabled)

**Step 4: Test update mechanism**

Run: `task agent-skills:update`
Expected: PASS (updates successfully or reports up-to-date)

**Step 5: Test status command**

Run: `task agent-skills:status`
Expected: PASS (shows current status)

**Step 6: Commit**

```bash
git add test-agent-skills.sh
git commit -m "test: add comprehensive agent skills integration tests"
```

### Task 9: Documentation

**Files:**
- Modify: `README.md` (add Agent Skills section)
- Create: `docs/agent-skills.md` (detailed documentation)

**Step 1: Write failing documentation test**

```bash
#!/usr/bin/env bash
# Test: Documentation completeness
set -euo pipefail

echo "Testing documentation..."

# Check if README mentions agent-skills
grep -q "agent-skills" README.md && echo "✓ README mentions agent-skills" || echo "✗ README missing agent-skills"

# Check if detailed documentation exists
test -f docs/agent-skills.md && echo "✓ Detailed documentation exists" || echo "✗ Detailed documentation missing"
```

**Step 2: Run test to verify it fails**

Run: `./test-docs.sh`
Expected: FAIL with missing documentation

**Step 3: Update README.md**

```markdown
# Add this section to README.md after the existing sections

## 🤖 Agent Skills Management

This configuration includes automatic management of AI agent skills for OpenCode and Claude Code integration.

### Features
- **Automatic Installation**: Skills install automatically with opencode or claude bundles
- **Upstream Updates**: Clean update mechanism from superpowers repository
- **Local Customization**: Override or extend skills in the repository
- **Cross-Platform**: Works on all configured systems (macOS and NixOS)
- **Validation**: Skills follow Agent Skills specification compliance

### Usage

```bash
# Check skills status
task agent-skills:status

# Update skills from upstream
task agent-skells:update

# Validate skills format
task agent-skells:validate

# List available skills
skills-list
```

### Configuration

Agent skills are automatically enabled when either `opencode` or `claude` bundles are active. Skills are installed to:
- `~/.config/opencode/skills/` - Primary skills directory
- `~/.config/opencode/superpowers/skills/` - Superpowers compatibility

See [docs/agent-skills.md](docs/agent-skills.md) for detailed documentation.
```

**Step 4: Create detailed documentation**

```markdown
# Create: docs/agent-skills.md
# Agent Skills Management

## Overview

This system provides comprehensive management of AI agent skills through Nix, ensuring consistent installation across all your development environments.

## Architecture

### Module Structure
```
modules/agent-skills/
├── default.nix          # Main module definition
├── skills.nix           # Skills installation logic
├── updates.nix          # Update mechanism
└── skills/              # Skill definitions
    ├── using-superpowers/
    ├── brainstorming/
    └── ...
```

### Integration Points

1. **Bundles Integration**: Auto-enabled by opencode/claude bundles
2. **Home-Manager Integration**: Manages file placement in user home directory
3. **Update System**: Git-based updates from upstream superpowers
4. **Task Integration**: Taskfile commands for common operations

## Usage Guide

### Checking Status
```bash
task agent-skills:status
```
Shows current skills count, version tracking, and directory status.

### Updating Skills
```bash
task agent-skells:update
```
Fetches latest skills from upstream superpowers repository while preserving custom skills.

### Validating Skills
```bash
task agent-skells:validate
```
Checks that all skills follow the Agent Skills specification.

### Listing Skills
```bash
skills-list
```
Lists all installed skills by name.

## Customization

### Adding Custom Skills
1. Create skill directory: `modules/agent-skills/skills/my-skill/`
2. Add `SKILL.md` with proper frontmatter
3. Rebuild system: `task build`

### Modifying Existing Skills
Edit skills in `modules/agent-skills/skills/` - changes will be applied on next rebuild.

### Disabling Auto-Updates
Set `myConfig.agent-skills.enableUpdates = false` in your configuration to disable automatic updates.

## Troubleshooting

### Skills Not Found
1. Check bundle is enabled: `task agent-skells:status`
2. Verify directories exist: `ls -la ~/.config/opencode/skills/`
3. Rebuild system: `task build`

### Update Failures
1. Check internet connectivity
2. Verify git access to GitHub
3. Check permissions on skills directories

### Specification Violations
1. Run validation: `task agent-skells:validate`
2. Check frontmatter format in `SKILL.md` files
3. Ensure directory names match skill names

## Development

### Adding New Update Sources
Modify `modules/agent-skills/updates.nix` to add additional upstream repositories.

### Extending Validation
Enhance validation logic in the `agent-skells:validate` task to check for additional requirements.

## Security Considerations

- Skills execute as part of AI assistant - review custom skills carefully
- Updates fetch from external repository - verify commit hashes
- Skills have access to system through AI assistant permissions
```

**Step 5: Run test to verify it passes**

Run: `./test-docs.sh`
Expected: PASS (documentation complete)

**Step 6: Commit**

```bash
git add README.md docs/agent-skills.md test-docs.sh
git commit -m "docs: add comprehensive agent skills documentation"
```

---

## Execution Handoff

Plan complete and saved to `docs/plans/2025-01-18-agent-skills-management.md`. Two execution options:

**1. Subagent-Driven (this session)** - I dispatch fresh subagent per task, review between tasks, fast iteration

**2. Parallel Session (separate)** - Open new session with executing-plans, batch execution with checkpoints

Which approach?