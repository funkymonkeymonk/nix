# Skills and Opencode Config Management Design

## Overview

Manage OpenCode user configurations and skill installations declaratively through Nix/home-manager, with progressive skill discovery based on enabled roles.

## Architecture

### Skills System

**Structure:**
```
modules/home-manager/skills/
├── manifest.nix       # Defines all available skills with metadata
├── definitions/       # Internal skill definitions
├── install.nix       # Installation logic based on enabled roles
└── fetch.nix        # External import mechanism (like Go imports)
```

**Manifest Entry:**
```nix
{
  name = "brainstorming";
  description = "Help turn ideas into designs";
  roles = ["developer" "creative"];  # Enabled when these roles active
  files = ./definitions/brainstorming;
  imports = [];  # External: ["github:user/repo//path"]
}
```

**Progressive Discovery:** Skills are installed based on enabled roles. Users discover more skills by adding roles to their bundle configuration.

**External Imports:** Syntax `github:owner/repo//skill-path` fetches from that repository path (similar to Go).

### Opencode Config

**Layered Merging (lowest to highest priority):**
1. **Base** - Default OpenCode config (MCP servers, base permissions)
2. **Role** - From bundles (developer adds dev tools, workstation adds work tools)
3. **Host** - From targets (machine-specific overrides)
4. **User** - Per-user overrides (wweaver vs monkey)

**Merge Strategy:** `lib.recursiveUpdate` merges config objects, allowing deep overrides.

## Implementation

### Files to Create/Modify

1. **Create:** `modules/home-manager/skills/manifest.nix` - Skill metadata
2. **Create:** `modules/home-manager/skills/install.nix` - Installation logic
3. **Create:** `modules/home-manager/skills/fetch.nix` - External imports
4. **Modify:** `modules/home-manager/opencode.nix` - Add role/host/user merging
5. **Modify:** `modules/common/options.nix` - Add skill options
6. **Remove:** `modules/home-manager/agent-skills/` - Old placeholder files
7. **Modify:** `bundles.nix` - Add per-role opencode configs and skills

## Data Flow

```
flake.nix (roles) 
  → bundles.nix (role configs + skills)
    → modules/home-manager/skills/install.nix (installs matching skills)
    → modules/home-manager/opencode.nix (merges configs)
      → home.file.".config/opencode/opencode.json"
      → home.file.".config/opencode/skills/<skill>/*"
```

## Benefits

- **Progressive discovery:** Users find new skills by enabling roles
- **Role-based organization:** Skills tied to work types
- **Flexible imports:** External skills from any git repo
- **Host/user isolation:** Different configs per machine and user
- **Declarative:** Full reproducibility via Nix
