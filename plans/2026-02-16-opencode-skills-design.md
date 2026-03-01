# OpenCode Configuration & Skills Management Design

## Overview

Manage user-level OpenCode configurations and skills declaratively through home-manager, with progressive skill discovery and role-based organization.

## Architecture

### Components

1. **Skills Module** (`modules/home-manager/skills/`)
   - `manifest.nix` - Registry of all available skills
   - `definitions/` - Internal skill implementations
   - `fetch.nix` - External import resolution (Go-like syntax)

2. **OpenCode Config Module** (`modules/home-manager/opencode.nix`)
   - Layered config merging (base → role → host → user)
   - Host-specific and user-specific configurations

3. **Bundle Integration**
   - Skills mapped to roles in `bundles.nix`
   - OpenCode config fragments in role definitions

---

## Skills Management

### Directory Structure

```
modules/home-manager/skills/
├── manifest.nix          # Skill registry with metadata
├── definitions/         # Internal skill files
│   ├── brainstorming.md
│   ├── debugging.md
│   ├── tdd.md
│   ├── writing.md
│   └── ...
├── fetch.nix            # External import logic
└── installer.nix       # Installs skills based on enabled roles
```

### Manifest Format

```nix
{
  # Example manifest entry
  brainstorming = {
    description = "Help turn ideas into fully formed designs";
    roles = ["developer" "creative"];
    files = ./definitions/brainstorming;
    imports = [];
  };

  debugging = {
    description = "Systematic debugging methodology";
    roles = ["developer"];
    files = ./definitions/debugging;
    imports = [];
  };

  # Future: external import example
  # external-skill = {
  #   description = "From external repo";
  #   roles = ["developer"];
  #   files = null;  # fetched from imports
  #   imports = ["github:user/skill-repo//skill-name"];
  # };
}
```

### Progressive Discovery

- Skills are installed based on enabled roles in bundle
- Adding a new role (e.g., "creative") installs its associated skills
- Users discover new capabilities by exploring role-based skill directories
- Skills directory structure: `~/.config/opencode/skills/<role>/<skill>.md`

### External Import Syntax

Similar to Go imports, supporting:
- `github:owner/repo//path` - Fetch from GitHub
- `gitlab:owner/repo//path` - Fetch from GitLab
- `local:./relative/path` - Relative to this repo

Implementation uses `builtins.fetchTarball` or `builtins.fetchGit`.

---

## OpenCode Config Layered Merging

### Priority Order (lowest to highest)

1. **Base** - Default config (MCP, tools, basic permissions)
2. **Role** - From bundles (developer adds permissions docker, creative adds ffmpeg)
3. **Host** - Machine-specific (different models,)
4. ** themesUser** - Per keys,-user overrides (API personaling Strategy preferences)

### Merg

```nix
lib.recursiveUpdate baseConfig [
  roleConfig
  hostConfig
  userConfig
]
```

### Config Fragments in Bundles

```nix
# bundles.nix
roles = {
  developer = {
    packages = [...];
    opencode = {
      permission.bash = {
        "docker *" = "allow";
        "kubectl *" = "allow";
      };
      mcp = {
        devenv = { enable = true; };
      };
    };
    skills = ["brainstorming" "debugging" "tdd"];
  };

  creative = {
    packages = [...];
    opencode = {
      permission.bash = {
        "ffmpeg *" = "allow";
        "convert *" = "allow";
      };
    };
    skills = ["brainstorming" "writing"];
  };
}
```

### Host/User Specific Configs

```nix
# targets/wweaver.nix
myConfig.opencode = {
  model = "claude-sonnet-4-20250514";
  theme = "dracula";
};

# targets/monkey.nix  
myConfig.opencode = {
  model = "opencode/kimi-k2.5-free";
  theme = "catppuccin";
};
```

---

## Data Flow

```
flake.nix
    │
    ├─► bundles.nix (roles + opencode config fragments + skills list)
    │
    ├─► modules/home-manager/skills/
    │       │
    │       ├─► manifest.nix (skill registry)
    │       │
    │       ├─► definitions/ (internal skill files)
    │       │
    │       └─► installer.nix (installs skills for enabled roles)
    │
    └─► modules/home-manager/opencode.nix
            │
            ├─► Collects role configs from bundles
            │
            ├─► Merges with host/user configs
            │
            └─► Generates opencode.json
```

---

## Error Handling

### Skills
- Missing skill file: Warning + skip, don't fail build
- Failed external fetch: Error with helpful message
- Duplicate skill names: First wins, warn about collision

### OpenCode Config
- Invalid JSON generated: Build fails (can't be runtime fixed)
- Missing required fields: Use defaults from base config

---

## Testing

1. **Syntax validation**: `nix flake check`
2. **Config generation**: `nix eval .#darwinConfigurations.wweaver.homeManagerConfiguration.activationPackage`
3. **Skill files exist**: Check generated output contains expected files
4. **JSON validity**: Parse generated opencode.json

---

## Migration Plan

1. **Phase 1**: Refactor current opencode.nix to use layered merging
2. **Phase 2**: Create skills module with manifest and installer
3. **Phase 3**: Remove old agent-skills module placeholders
4. **Phase 4**: Add skill definitions for existing roles
5. **Phase 5**: Add external import functionality

---

## Future Enhancements

- **Skill dependencies**: Skill A requires Skill B
- **Runtime updates**: `update-skills` command for fresh external imports
- **Skill templates**: Generate new skills from templates
- **Skill testing**: Validate skill syntax before installation
