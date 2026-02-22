---
name: devenv-init
description: >
  Use when initializing a new project with devenv, direnv, and jj version control.
  Triggers on: setting up dev environment, configuring nix shell, project bootstrap.
---

# Initialize Devenv + Direnv + JJ

## Overview

Bootstrap a development environment with jj (git-backed), devenv (nix-based tools), and direnv (auto-activation). **Idempotent** - safe to run multiple times to update configuration.

## Quick Start

```bash
bash .claude/skills/devenv-init/setup-devenv.sh           # Full setup
bash .claude/skills/devenv-init/setup-devenv.sh --force   # Regenerate devenv.nix
bash .claude/skills/devenv-init/setup-devenv.sh --analyze # Analyze only
```

## What It Does

1. **Ensures jj repo** - Initializes if git exists but jj doesn't
2. **Warns on missing remotes** - Continues anyway
3. **Analyzes repo** - Detects language, tools, scripts, tasks
4. **Creates/updates .envrc** - Works with OR without devenv
5. **Generates devenv.nix** - With detected configuration
6. **Creates devenv.yaml** - Nixpkgs input

## Auto-Detection

| Detected | Source | Generated Config |
|----------|--------|------------------|
| Rust | Cargo.toml | languages.rust, cargo-watch, rustfmt/clippy hooks |
| Python | pyproject.toml | languages.python, ruff, uv, pytest |
| Node | package.json | languages.javascript, pnpm/yarn, scripts from package.json |
| Go | go.mod | languages.go, golangci-lint, gofmt hook |
| Tools | Makefile, justfile | packages (gnumake, just) |

## Idempotency

| File | Behavior on Re-run |
|------|-------------------|
| .envrc | Updates if managed, backs up if not |
| devenv.nix | Skips unless --force, backs up if unmanaged |
| devenv.yaml | Skips if exists |
| .jj | Initializes only if missing |

Files managed by this skill contain a marker comment. Unmanaged files are backed up before overwriting.

## Options

```
--force, -f    Regenerate devenv.nix even if already managed
--analyze, -a  Only analyze repo, show recommendations, don't write
--help, -h     Show help
```

## Generated Sections

| Section | Auto-populated From |
|---------|-------------------|
| packages | Detected tools (cargo-watch, ruff, pnpm, etc) |
| scripts | Common dev commands (check, lint, test, dev) |
| tasks | Build/test commands for `devenv tasks run` |
| processes | Dev servers from package.json scripts |
| pre-commit.hooks | Language-appropriate formatters/linters |

## .envrc Behavior

The generated `.envrc` gracefully handles:

1. **devenv installed**: Full devenv shell activation
2. **nix only**: Falls back to `use_nix`
3. **Neither**: Succeeds silently (no-op)

## Querying Devenv Options

Use `devenv-query.sh` to explore available options without loading full docs:

```bash
# List all available languages
bash .claude/skills/devenv-init/devenv-query.sh langs

# List all available services
bash .claude/skills/devenv-init/devenv-query.sh services

# Search options for a specific feature
bash .claude/skills/devenv-init/devenv-query.sh options languages.rust
bash .claude/skills/devenv-init/devenv-query.sh options services.postgres

# Search nixpkgs for packages
bash .claude/skills/devenv-init/devenv-query.sh packages ripgrep

# Evaluate current devenv.nix config (returns JSON)
bash .claude/skills/devenv-init/devenv-query.sh eval languages.rust.enable
```

Results are cached for 24h in `~/.cache/devenv-init/`.

## Troubleshooting

| Issue | Fix |
|-------|-----|
| "No git or jj repository" | Run `git init` first |
| "Not git-backed" | Run `jj git init --colocate` |
| Want to regenerate | Run with `--force` |
| Wrong detection | Edit devenv.nix manually, it won't be overwritten |
| Need option details | Run `devenv-query.sh options <path>` |
