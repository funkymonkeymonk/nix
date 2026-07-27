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

### System Configuration

| Task | Description |
|------|-------------|
| `system:switch` | Apply configuration to current system (platform-aware) |
| `system:init` | Initial setup commands (Darwin only) |

### Validation

| Task | Description |
|------|-------------|
| `validate:disko` | Validate disko disk configurations |
| `validate:install-script` | Validate install-machine.sh script |

### Code Quality

| Task | Description |
|------|-------------|
| `check:lint` | Run lint checks (formatting + static analysis) |

### Testing

| Task | Description |
|------|-------------|
| `test:eval` | Evaluate all NixOS and Darwin configurations (gates builds) |
| `test:nixos-eval` | Validate NixOS configs can be evaluated (catches module errors) |
| `test:checks` | Run nix-unit eval tests (fast, no derivation builds) |
| `test:all` | Run all tests (eval gates build, optimized for parallel CI) |
| `test:sketchybar` | Test sketchybar options, theme, and color conversion |
| `test:onepassword` | Test 1Password options, guard, and config output |

### Flake Management

| Task | Description |
|------|-------------|
| `flake:update` | Update the nix flake to latest versions |

### Documentation

| Task | Description |
|------|-------------|
| `docs:update` | Update and validate documentation (Diataxis) |
| `docs:validate` | Validate documentation structure only |
| `docs:generate` | Generate reference documentation only |

### Agent Skills

| Task | Description |
|------|-------------|
| `agent-skills:status` | Check agent skills status |
| `agent-skills:update` | Update agent skills from upstream superpowers |
| `agent-skills:validate` | Validate skills against Agent Skills specification |

### Profiling

| Task | Description |
|------|-------------|
| `profile:llm` | Profile LLM inference performance via env vars (`MODEL`, `PROMPTS`, `MAX_TOKENS`) |

## Shell Commands (Not Tasks)

These are shell functions/aliases available inside the devenv shell, distinct
from `devenv tasks run <name>`:

| Command | What It Does |
|---------|---------------|
| `s` / `switch` | Runs `system:switch` (workspace-aware: runs from the jj repo root if you're in a workspace) |
| `ide` | Launches a zellij session with a file manager, editor, and AI agent panes |
| `pr-review` | Launches a zellij session running `gh-dash` for reviewing PRs |
| `skills-list` | Lists installed agent skill names (`SKILL.md` files under the agent skills path) |
| `agentsudo` | Runs a sudo command using the 1Password-stored sudo password for the current host |

## Shell Aliases

After entering the devenv shell:

| Alias | Expands To |
|-------|------------|
| `dt <task>` | `devenv tasks run <task>` |
| `dtr <task>` | `devenv tasks run <task>` |
| `dtl` | `devenv tasks list` |

> **See also:** [How-To: Run CI Locally](../how-to/run-ci-locally.md) for a task-oriented walkthrough.
