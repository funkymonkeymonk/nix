# Agents Guide

This guide helps AI agents understand and work effectively with this Nix system configuration repository.

## Repository Overview

This is a modular Nix Flakes configuration for managing macOS and NixOS systems with home-manager. It uses a sophisticated architecture with modules, bundles, and role-based configurations.

## Key Concepts

### Architecture
- **Modules**: Reusable configuration logic (how things work)
- **Bundles**: Package collections (what gets installed) 
- **Targets**: Machine-specific configurations
- **Options**: Type-safe configuration with validation

### Directory Structure
```
.
├── .github/                    # GitHub Actions workflows
├── bundles/                    # Package collections by role/platform
│   ├── base/                   # Essential packages
│   ├── roles/                  # Role-based bundles (developer, creative, etc.)
│   └── platforms/              # Platform-specific packages
├── modules/                    # Reusable Nix configurations
│   ├── common/                 # Shared configurations
│   ├── home-manager/           # User environment modules
│   └── nixos/                  # Linux-specific modules
├── targets/                    # Machine-specific configurations
├── os/                         # Platform OS configurations
├── templates/                  # Templates for new configurations
├── flake.nix                   # Main Nix flake definition
├── devenv.nix                  # Development environment configuration
└── Taskfile.yml               # Task automation
```

## Available Tasks

Use `task <command>` for common operations:

### Testing and Building
- `task test` - Basic flake validation
- `task test:full` - Comprehensive cross-platform validation
- `task build` - Build all systems
- `task build:darwin` - Build macOS configurations only
- `task build:nixos` - Build Linux configurations only

### Code Quality
- `task fmt` - Format Nix files with alejandra
- `task lint` - Run linters (deadnix)
- `task quality` - Run all code quality checks

### Development Environment
- `task dev` - Enter development shell with all tools
- `task devenv:update` - Update devenv lock file

### Agent Skills Management
- `task agent-skills:status` - Check skills status
- `task agent-skills:update` - Update skills from upstream
- `task agent-skills:validate` - Validate skills format

### Secrets Management (1Password)
- `task 1password:setup` - Set up 1Password CLI authentication
- `task 1password:status` - Check 1Password CLI status
- `task secrets:init` - Initialize secrets template
- `task secrets:populate` - Auto-populate secrets from 1Password items

## Working with This Repository

### Before Making Changes
1. Always run `task test:full` to validate the current state
2. Check existing code style by running `task fmt` 
3. Use the development shell with `task dev` for proper tooling

### Making Changes
1. Create or modify files as needed
2. Run `task fmt` to format code
3. Run `task lint` to check for issues
4. Run `task test:full` to validate changes
5. Commit with descriptive messages

### Adding New Features
1. **New Machine**: Create target in `targets/`, update `flake.nix`
2. **New Role**: Create bundle in `bundles/roles/`
3. **New Module**: Create in appropriate `modules/` subdirectory
4. **New Option**: Add to `modules/common/options.nix`

## Agent Skills Integration

This repository includes automatic AI agent skills management:
- Skills auto-install with `opencode` or `claude` bundles
- Installed to `~/.config/opencode/skills/` and `~/.config/opencode/superpowers/skills/`
- Use `task agent-skills:status` to check current state
- Skills follow Agent Skills specification

## Platform Support

### Supported Systems
- **macOS**: nix-darwin configuration (aarch64-darwin)
- **Linux**: NixOS configuration (x86_64-linux)

### Cross-Platform Validation
The `task test:full` command validates both platforms regardless of host:
- On macOS: Tests both Darwin and Linux configs
- On Linux: Tests both Linux and Darwin configs
- Uses dry-run builds for cross-architecture validation

## Code Style Guidelines

### Nix Files
- Use alejandra formatter (`task fmt`)
- Remove dead code (checked by deadnix)
- Follow existing patterns and conventions
- Use type-safe options with proper validation

### Commit Messages
- Use conventional commits: `feat:`, `fix:`, `docs:`, etc.
- Be concise but descriptive
- Reference relevant files or components

## Security Considerations

### Secrets Management
- Uses 1Password CLI for runtime secret access
- Secrets never stored in repository or Nix store
- SSH agent integration for key management
- Git commit signing via 1Password SSH signing

### Code Review
- All changes should pass `task quality` checks
- Validate cross-platform compatibility
- Review security implications of module changes

## Troubleshooting

### Common Issues
1. **Build failures**: Check `task test:full` output for specific errors
2. **Formatting issues**: Run `task fmt` to fix style problems
3. **Cross-platform issues**: Ensure platform-specific dependencies are correct
4. **Skills issues**: Use `task agent-skills:validate` to check skills format

### Getting Help
- Check existing documentation in `docs/`
- Review Taskfile.yml for available commands
- Examine similar configurations in the codebase
- Use built-in validation tools to diagnose issues

## Development Workflow

1. **Setup**: `task dev` to enter development environment
2. **Validate**: `task test:full` to ensure clean state
3. **Implement**: Make changes following existing patterns
4. **Quality**: `task quality` to run all checks
5. **Test**: `task test:full` to validate changes
6. **Commit**: Use conventional commit messages

This workflow ensures consistent, high-quality contributions to the configuration repository.