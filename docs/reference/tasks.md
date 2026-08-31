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

## Task Conventions

Tasks follow a `namespace:action` naming convention:

| Pattern | Meaning | Example |
|---------|---------|---------|
| `*:all` | **Aggregate** — runs all tasks in the namespace | `check:all`, `test:all` |
| `*:name` | **Leaf** — specific operation | `check:lint`, `test:eval` |

Run the aggregate when you want everything in a category. Run the leaf when you want a specific thing.

## Available Tasks

### Quality Checks

| Task | Description | Typical Duration |
|------|-------------|-----------------|
| `check:all` | Lint + unit tests + config eval | ~30s |
| `check:lint` | Formatting (alejandra), dead code (deadnix), static analysis (statix), YAML | ~10s |
| `check:unit` | nix-unit eval tests (fast, no builds) | ~5s |

### Testing

| Task | Description | Typical Duration |
|------|-------------|-----------------|
| `test:all` | Eval + build checks + module tests | 2–10min |
| `test:eval` | Evaluate all NixOS and Darwin configurations | ~10s |
| `test:build` | Build all flake check targets (single eval) | 2–10min |
| `test:sketchybar` | Sketchybar module tests | ~30s |
| `test:onepassword` | 1Password module tests | ~30s |

### Documentation

| Task | Description |
|------|-------------|
| `docs:all` | Update + validate + generate |
| `docs:update` | Update and validate documentation (Diataxis) |
| `docs:validate` | Validate documentation structure only |
| `docs:generate` | Generate reference documentation only |

### System

| Task | Description |
|------|-------------|
| `system:switch` | Apply configuration to current system (platform-aware) |
| `system:init` | Initial nix-darwin setup (macOS only) |

### Validation

| Task | Description |
|------|-------------|
| `validate:all` | Disko + install-script validation |
| `validate:disko` | Validate disko disk configurations |
| `validate:install-script` | Validate install-machine.sh syntax |

### Agent Skills

| Task | Description |
|------|-------------|
| `agent-skills:all` | Status + update + validate |
| `agent-skills:status` | Check skills installation status |
| `agent-skills:update` | Update skills from upstream superpowers |
| `agent-skills:validate` | Validate skills format |

### LLM / Benchmarking

| Task | Description |
|------|-------------|
| `benchmark:all` | Run all benchmark suites |
| `benchmark:lm-eval-gsm8k` | lm-eval GSM8K against local oMLX |
| `benchmark:lm-eval-mini` | Quick lm-eval smoke benchmark |
| `benchmark:lm-eval-leaderboard` | HuggingFace Open LLM Leaderboard v2 |
| `benchmark:lighteval-gsm8k` | lighteval GSM8K |
| `benchmark:bfcl-smoke` | BFCL function-calling smoke test against local oMLX |
| `smoke:llm-stack` | Smoke test oMLX + Bifrost |

### Maintenance

| Task | Description |
|------|-------------|
| `flake:update` | Update flake inputs to latest versions |

## Dependency Graph

The `*:all` aggregates use devenv's `after` mechanism to run leaves in the correct order:

```
check:all
├── check:lint
└── check:unit
    └── test:eval

test:all
├── test:eval
├── test:build
├── test:sketchybar
└── test:onepassword
```

Dependencies are declared, not orchestrated via shell — devenv handles scheduling.

## Shell Aliases

After entering the devenv shell:

| Alias | Expands To |
|-------|------------|
| `dt <task>` | `devenv tasks run <task>` |
| `dtr <task>` | `devenv tasks run <task>` |
| `dtl` | `devenv tasks list` |
| `s` | `devenv tasks run system:switch` |
| `switch` | `devenv tasks run system:switch` |
