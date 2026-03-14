# Nix System Configuration

A modular Nix Flakes configuration for managing macOS and NixOS systems.

## Features

- **Multi-platform**: macOS (nix-darwin) and NixOS with unified configuration
- **Modular architecture**: Role-based bundles for different use cases
- **AI agent skills**: Automatic management of OpenCode and Claude Code skills
- **1Password integration**: SSH authentication and commit signing
- **CI/CD pipeline**: Automated validation and caching

## Quick Start

```bash
# Clone and enter development environment
git clone https://github.com/funkymonkeymonk/nix.git
cd nix
nix develop

# Run validation
devenv tasks run check:all

# Apply configuration (macOS)
darwin-rebuild switch --flake .#<hostname>
```

> **New here?** See the [Getting Started tutorial](docs/tutorials/getting-started.md).

## Documentation

| Type | Description |
|------|-------------|
| [Tutorials](docs/tutorials/) | Learning-oriented walkthroughs |
| [How-To Guides](docs/how-to/) | Task-oriented instructions |
| [Reference](docs/reference/) | Technical specifications |
| [Explanation](docs/explanation/) | Design and architecture |

### Common Tasks

- [Add a new machine](docs/how-to/add-machine.md)
- [Add a new role](docs/how-to/add-role.md)
- [Run CI locally](docs/how-to/run-ci-locally.md)
- [Set up 1Password signing](docs/how-to/setup-1password.md)

## Project Structure

```
├── modules/          # Reusable Nix configurations
│   ├── common/       # Shared options, users, shell
│   ├── home-manager/ # User environment, skills
│   └── nixos/        # NixOS-specific modules
├── targets/          # Machine-specific configurations
├── bundles.nix       # Role definitions (packages, skills)
├── flake.nix         # Main flake with helper functions
└── docs/             # Documentation (Diataxis)
```

> **Learn more:** [Architecture explanation](docs/explanation/architecture.md)

## Available Roles

| Role | Description |
|------|-------------|
| `base` | Essential tools (always included) |
| `developer` | Development environment |
| `creative` | Media tools |
| `desktop` | Desktop applications |
| `workstation` | Work tools |
| `entertainment` | Entertainment apps (macOS) |
| `gaming` | Gaming tools |
| `llm-client` | OpenCode + rtk + agent skills |
| `llm-claude` | Claude Code + agent skills |
| `llm-host` | Ollama |

> **Full list:** [Roles reference](docs/reference/roles.md)

## Shell Aliases

After entering devenv shell:

| Alias | Command |
|-------|---------|
| `s` | `devenv tasks run system:switch` |
| `q` | `devenv tasks run check:all` |
| `b` | `devenv tasks run build:all` |

> **All tasks:** [Tasks reference](docs/reference/tasks.md)

## For AI Agents

See [AGENTS.md](AGENTS.md) for AI-specific guidance on working with this repository.

## TODO

- [x] **Multi-Agent Repository Workflow Module**: Fast Jujutsu Workflow (`fjj`)
  - ✅ Disko configuration for `/srv` volume (in module)
  - ✅ Local GitHub mirrors in `/srv/github/` per configured project
  - ✅ Automatic sync (5min during agent sessions, 1hr idle)
  - ✅ Per-agent jj workspaces in `~/workspaces/`
  - ✅ Stacked PR support with conventional branch naming
  - ✅ Auto-cleanup after merge
  - ✅ `fjj` command with fzf integration for universal entry

## License

MIT
