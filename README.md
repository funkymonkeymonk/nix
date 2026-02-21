# Nix System Configuration

A modular Nix Flakes configuration for managing macOS and NixOS systems with home-manager.

## Features

- **Multi-platform**: macOS (nix-darwin) and Linux (NixOS)
- **Modular**: Role-based bundles for different use cases
- **Reproducible**: Declarative configuration with locked dependencies
- **Automated**: CI/CD, pre-commit hooks, weekly updates
- **AI-integrated**: Agent skills management for OpenCode and Claude Code

## Quick Start

Bootstrap a new machine:

```bash
curl -fsSL https://raw.githubusercontent.com/funkymonkeymonk/nix/main/bootstrap.sh | bash
```

> For a complete walkthrough, see the [Getting Started Tutorial](docs/tutorials/getting-started.md).

## Documentation

### Tutorials (Learning)

- [Getting Started](docs/tutorials/getting-started.md) - Set up your first machine

### How-To Guides (Tasks)

- [Add a New Machine](docs/how-to/add-new-machine.md)
- [Add a New Role](docs/how-to/add-new-role.md)
- [Add a Custom Skill](docs/how-to/add-custom-skill.md)
- [Set Up SSH Commit Signing](docs/how-to/setup-ssh-signing.md)
- [Update Flake Dependencies](docs/how-to/update-flake.md)

### Reference (Information)

- [Roles](docs/reference/roles.md) - Available roles and their packages
- [Tasks](docs/reference/tasks.md) - Available devenv tasks
- [Skills](docs/reference/skills.md) - Agent skills reference
- [Directory Structure](docs/reference/directory-structure.md)

### Explanation (Understanding)

- [Architecture](docs/explanation/architecture.md) - System design and rationale
- [Agent Skills Design](docs/explanation/agent-skills-design.md)
- [Secrets Management](docs/explanation/secrets-management.md)

## Common Commands

```bash
devenv tasks run switch      # Apply configuration
devenv tasks run test        # Validate configuration
devenv tasks run quality     # Run code quality checks
devenv tasks list            # See all available tasks
```

## Project Structure

```
├── modules/          # Reusable configurations
├── targets/          # Machine-specific configs
├── bundles.nix       # Role definitions
├── flake.nix         # Main entry point
└── docs/             # Documentation
```

> See [Directory Structure](docs/reference/directory-structure.md) for details.

## Supported Platforms

| Platform | Architecture | Example Machines |
|----------|--------------|------------------|
| macOS    | aarch64-darwin | Will-Stride-MBP, MegamanX |
| NixOS    | x86_64-linux | drlight, zero |

## Contributing

1. Enter development environment: `devenv shell`
2. Make changes following existing patterns
3. Run quality checks: `devenv tasks run quality`
4. Validate: `devenv tasks run test:full`
5. Commit with conventional messages

## Status

**Complete:**
- Modular configuration system
- Cross-platform support
- CI/CD pipeline
- Agent skills integration
- Secret management with 1Password

**In Progress:**
- Performance optimizations

**Planned:**
- GUI application management
- Backup automation
