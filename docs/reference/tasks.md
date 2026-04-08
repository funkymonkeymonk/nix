# Tasks Reference

Tasks are defined in `devenv.nix` and provide common operations.

## Running Tasks

```bash
devenv tasks run <task-name>
```

Or use the shell alias:
```bash
dt <task-name>
dtr <task-name>
```

List all tasks:
```bash
devenv tasks list
dtl
```

## Available Tasks

### Configuration

| Task | Description |
|------|-------------|
| `switch` | Apply configuration to current system |
| `init` | Initial setup commands for nix-darwin |
| `build` | Build all configurations (dry-run) |
| `build:darwin` | Build all Darwin (macOS) configurations |
| `build:nixos` | Build all NixOS configurations |

### Build

| Task | Description |
|------|-------------|
| `build:all` | Build all configurations (dry-run) |
| `build:darwin` | Build Darwin configurations (dry-run) |
| `build:nixos` | Build NixOS configurations (dry-run) |

### Code Quality

| Task | Description |
|------|-------------|
| `quality` | Run all quality checks (format + lint) |
| `fmt` | Format all Nix files with alejandra |

### Flake Management

| Task | Description |
|------|-------------|
| `flake:update` | Update flake inputs |
| `devenv:update` | Update devenv lock file |

### Development

| Task | Description |
|------|-------------|
| `ide` | Launch zellij IDE with file explorer and agent |
| `pr:review` | Launch PR review dashboard (gh-dash) |

### Agent Skills

| Task | Description |
|------|-------------|
| `agent-skills:status` | Check skills installation status |
| `agent-skills:update` | Update skills from upstream superpowers |
| `agent-skills:validate` | Validate skills format |

### Git Remote

| Task | Description |
|------|-------------|
| `git:set-remote-ssh` | Switch git remote to SSH |
| `git:set-remote-https` | Switch git remote to HTTPS |

### Cachix

| Task | Description |
|------|-------------|
| `cachix:push` | Build current host config and push to Cachix |
| `cachix:push:all` | Build all configs for current platform and push |

### Documentation

| Task | Description |
|------|-------------|
| `docs:update` | Update and validate documentation |
| `docs:validate` | Validate documentation structure |
| `docs:generate` | Generate reference documentation |

## Cross-Platform Validation

The `test:full` task validates both platforms regardless of host:

- On Darwin: Tests Darwin and Linux configurations
- On Linux: Tests Linux and Darwin configurations

Validation includes:
- Flake structure and syntax (`nix flake check`)
- Build plans (`nix build --dry-run`)
- Configuration evaluation (`nix eval`)

## Shell Aliases

After configuration is applied:

| Alias | Expands To |
|-------|------------|
| `dt <task>` | `devenv tasks run <task>` |
| `dtr <task>` | `devenv tasks run <task>` |
| `dtl` | `devenv tasks list` |
| `skills-list` | List installed agent skills |
