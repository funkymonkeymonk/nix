# Agent Skills Management

## Overview

This system provides comprehensive management of AI agent skills through Nix, ensuring consistent installation across all your development environments.

## Architecture

### Module Structure
```
modules/home-manager/skills/
├── install.nix              # Skills installation logic (home-manager module)
├── manifest.nix             # Skill definitions with role assignments
├── internal/                # Skills defined in this repository
│   ├── brainstorming/
│   ├── debugging/
│   ├── tdd/
│   ├── writing-plans/
│   ├── writing-skills/
│   ├── verification-before-completion/
│   ├── receiving-code-review/
│   ├── requesting-code-review/
│   └── using-superpowers/
└── external/                # Skills adapted from external sources
    └── jj/                  # Jujutsu version control skill
```

### Integration Points

1. **Bundles Integration**: Auto-enabled by `llm-client` or `llm-claude` roles (via `enableAgentSkills` flag)
2. **Home-Manager Integration**: Manages file placement in `~/.config/opencode/skills/`
3. **Role-Based Filtering**: Skills are installed based on enabled roles in `myConfig.skills.enabledRoles`
4. **Task Integration**: Taskfile commands for common operations

### Configuration Flow

1. `flake.nix` → `mkBundleModule` sets `myConfig.skills.enabledRoles` based on active roles
2. `modules/common/users.nix` imports `skills/install.nix` when `myConfig.agent-skills.enable` is true
3. `skills/install.nix` filters `manifest.nix` by enabled roles and creates `home.file` entries
4. Skills are symlinked to `~/.config/opencode/skills/<skill-name>/`

## Usage Guide

### Checking Status
```bash
task agent-skills:status
```
Shows current skills count, version tracking, and directory status.

### Updating Skills
```bash
task agent-skills:update
```
Fetches latest skills from upstream superpowers repository while preserving custom skills.

### Validating Skills
```bash
task agent-skills:validate
```
Checks that all skills follow the Agent Skills specification.

### Listing Skills
```bash
skills-list
```
Lists all installed skills by name.

## Customization

### Adding Custom Skills

1. Create skill directory in `modules/home-manager/skills/internal/my-skill/`
2. Add `SKILL.md` with proper frontmatter:
   ```markdown
   ---
   name: my-skill
   description: Brief description of what the skill does
   ---
   
   # Skill Content Here
   ```
3. Register in `modules/home-manager/skills/manifest.nix`:
   ```nix
   "my-skill" = {
     description = "Brief description";
     roles = ["developer"];  # Which roles get this skill
     source = {
       type = "internal";
       path = ./internal/my-skill;
     };
     deps = [];  # Other skills this depends on
   };
   ```
4. Rebuild system: `darwin-rebuild switch` or `nixos-rebuild switch`

### Adding External Skills

For skills adapted from other sources:

1. Create directory in `modules/home-manager/skills/external/skill-name/`
2. Add the skill content
3. Register in manifest with `type = "internal"` (external fetching not yet implemented)

### Modifying Existing Skills

Edit skills in `modules/home-manager/skills/internal/` or `external/` - changes apply on next rebuild.

## Available Skills

Skills are assigned to roles in `manifest.nix`:

| Skill | Description | Roles |
|-------|-------------|-------|
| `brainstorming` | Collaborative design dialogue | developer, creative |
| `debugging` | Systematic debugging approach | developer |
| `tdd` | Test-driven development workflow | developer |
| `writing-plans` | Implementation plan creation | developer |
| `writing-skills` | Documentation and skill writing | developer, creative |
| `verification-before-completion` | Pre-completion verification | developer |
| `receiving-code-review` | Process review feedback | developer, workstation |
| `requesting-code-review` | Prepare and request reviews | developer, workstation |
| `using-superpowers` | Access available skills | llm-client, llm-claude |
| `jj` | Jujutsu version control | developer, llm-client, llm-claude |

## Troubleshooting

### Skills Not Found

1. Verify `agent-skills.enable = true` in your configuration
2. Check that roles with skills are enabled (e.g., `developer`, `llm-client`)
3. Rebuild system: `darwin-rebuild switch` or `nixos-rebuild switch`
4. Verify directories exist: `ls -la ~/.config/opencode/skills/`

### Skills Not Updating After Changes

1. Skills are symlinked from Nix store - must rebuild to apply changes
2. Run `darwin-rebuild switch` or `nixos-rebuild switch`

### Specification Violations

1. Run validation: `task agent-skills:validate`
2. Check frontmatter format in `SKILL.md` files
3. Ensure directory names match skill names in manifest

## Development

### Adding New Roles

To make skills available to a new role:

1. Add the role name to the skill's `roles` list in `manifest.nix`
2. Skills will automatically install for users with that role enabled

### Skill Dependencies

Skills can declare dependencies on other skills:

```nix
"my-skill" = {
  # ...
  deps = ["brainstorming" "debugging"];  # Will also install these
};
```

Dependencies are installed even if the user's roles wouldn't normally include them.

## Security Considerations

- Skills execute as part of AI assistant - review custom skills carefully
- Skills are symlinked from Nix store, providing immutability
- Changes require explicit rebuild to take effect