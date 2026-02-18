# Agents Guide

This guide helps AI agents understand and work effectively with this Nix system configuration repository.

## Repository Overview

This repository manages the configuration of all computers via Nix flakes. The purpose is to maintain declarative configurations that define system setups, packages, and settings. **Agents should only modify the Nix configuration files in this repository - never attempt to directly change the computers' configurations.**

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
├── modules/                    # Reusable Nix configurations
│   ├── common/                 # Shared configurations (options, users, shell, onepassword)
│   ├── home-manager/           # User environment modules
│   │   └── skills/             # Agent skills management
│   │       ├── install.nix     # Skills installation module
│   │       ├── manifest.nix    # Skill definitions and role assignments
│   │       ├── internal/       # Skills defined in this repo
│   │       └── external/       # Skills adapted from external sources
│   └── nixos/                  # Linux-specific modules
├── targets/                    # Machine-specific configurations
├── os/                         # Platform OS configurations
├── templates/                  # Templates for new configurations
├── bundles.nix                 # Consolidated package collections (roles + platforms)
├── flake.nix                   # Main Nix flake definition
├── devenv.nix                  # Development environment configuration
└── Taskfile.yml               # Task automation
```

## Available Tasks

Use task for common operations
Run `task --list` for a list of all tasks available and a quick definition

## Working with This Repository

### Before Making Changes
1. Always run `task test:full` to validate the current state
2. Check existing code style by running `task fmt`
3. Use the development shell with `task dev` for proper tooling

### Making Changes
1. Create or modify files as needed
2. Run `task quality` to format and lint code
3. Run `task test:full` to validate changes
4. Commit with descriptive messages

### Adding New Features
1. **New Machine**: Create target in `targets/`, update `flake.nix` using `mkUser` and `mkNixHomebrew` helpers
2. **New Role**: Add role to `bundles.nix` under `roles` attribute
3. **New Module**: Create in appropriate `modules/` subdirectory
4. **New Option**: Add to `modules/common/options.nix`

### Available Roles (in bundles.nix)
- `base` - Essential packages and shell aliases
- `developer` - Development tools (emacs, docker, k8s tools)
- `creative` - Media tools (ffmpeg, imagemagick)
- `desktop` - Desktop applications (logseq)
- `workstation` - Work tools (slack, trippy)
- `entertainment` - Entertainment apps (steam, obs, discord via homebrew)
- `gaming` - Gaming tools (moonlight-qt)
- `agent-skills` - AI agent skills management
- `llm-client` - OpenCode with LLM server connection
- `llm-claude` - Claude Code integration
- `llm-host` - Ollama for local model hosting
- `llm-server` - LiteLLM server (placeholder)

### Helper Functions (in flake.nix)
- `mkUser` - Creates standard user configuration
- `mkNixHomebrew` - Creates homebrew configuration for Darwin
- `mkBundleModule` - Creates bundle module from role list
- `commonModules` - Shared module imports for all systems

### Computed Options
- `myConfig.isDarwin` - Boolean for platform detection (use instead of manual checks)

## Agent Skills Integration

This repository includes automatic AI agent skills management:
- Skills auto-install when `agent-skills.enable = true` and roles like `developer`, `llm-client`, or `llm-claude` are active
- Skills are defined in `modules/home-manager/skills/manifest.nix` with role-based filtering
- Installed to `~/.config/opencode/skills/` via home-manager symlinks
- Use `task agent-skills:status` to check current state
- Skills follow Agent Skills specification

### Adding New Skills

1. Create skill directory in `modules/home-manager/skills/internal/skill-name/`
2. Add `SKILL.md` with frontmatter (`name`, `description`)
3. Register in `modules/home-manager/skills/manifest.nix` with role assignments
4. Rebuild system to install

### Version Control Preference (Jujutsu/jj)

When working in repositories that use Jujutsu (jj) for version control:

1. **Auto-detect jj repositories**: Check for `.jj/` directory (colocated repos have both `.jj/` and `.git/`)
2. **Use jj skill**: Load the `jj` skill when:
   - A `.jj/` directory exists in the repository
   - The user asks for any git-related operations (commit, push, log, diff, etc.)
   - The user explicitly mentions jj or Jujutsu

3. **Key jj principles to follow**:
   - Working copy IS a commit (no staging area)
   - Always run `jj status` first before any operation
   - Create new commits with `jj new` before starting work
   - Use `jj describe` to set commit messages
   - Never mix git and jj commands in the same session

4. **The jj skill is available at**: `~/.config/opencode/skills/jj/SKILL.md` (installs automatically with `opencode` bundle)

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
