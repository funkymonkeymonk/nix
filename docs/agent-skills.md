# Agent Skills Management

## Overview

This system provides comprehensive management of AI agent skills through Nix, ensuring consistent installation across all your development environments.

## Architecture

### Module Structure
```
modules/home-manager/agent-skills/
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
1. Create skill directory: `modules/home-manager/agent-skills/skills/my-skill/`
2. Add `SKILL.md` with proper frontmatter
3. Rebuild system: `task build`
4. Skills will be automatically installed to user directories

### Modifying Existing Skills
Edit skills in `modules/home-manager/agent-skills/skills/` - changes will be applied on next rebuild.

## Troubleshooting

### Skills Not Found
1. Check bundle is enabled: `task agent-skills:status`
2. Verify directories exist: `ls -la ~/.config/opencode/skills/`
3. Rebuild system: `task build`

### Update Failures
1. Check internet connectivity
2. Verify git access to GitHub
3. Check permissions on skills directories

### Specification Violations
1. Run validation: `task agent-skills:validate`
2. Check frontmatter format in `SKILL.md` files
3. Ensure directory names match skill names

## Development

### Adding New Update Sources
Modify `modules/home-manager/agent-skills/updates.nix` to add additional upstream repositories.

### Extending Validation
Enhance validation logic in `Taskfile.yml` to check for additional requirements.

## Security Considerations

- Skills execute as part of AI assistant - review custom skills carefully
- Updates fetch from external repository - verify commit hashes
- Skills have access to system through AI assistant permissions