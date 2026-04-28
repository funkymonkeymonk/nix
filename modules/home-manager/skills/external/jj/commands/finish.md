---
description: Orchestrate complete PR workflow by composing individual skills
agent: build
---

Run the complete PR workflow by composing specialized skills.

## Overview

`/finish` is an orchestrator that combines multiple standalone skills. Each skill can be used independently for more control.

## Workflow

This command runs these skills in sequence:

1. **[push skill]** - Push bookmark to origin
2. **[pr skill]** - Create PR if one doesn't exist
3. **[watch-ci-jobs skill]** - Monitor CI with intelligent polling

Stop here - human merges the PR.

## Usage

```bash
jj-finish [--max-retries N] [--dry-run]
```

## Options

- `--max-retries N` - Maximum retry attempts on failure (default: 5)
- `--dry-run` - Show what would be done without executing

## Examples

```bash
jj-finish              # Push, create PR, watch CI
jj-finish --dry-run    # Preview workflow without executing
```

## Individual Skills

Use these skills independently for more control:

| Skill | Command | Purpose |
|-------|---------|---------|
| push | `/push` or `jj-push` | Push bookmark to origin |
| pr | `/pr` or `jj-pr` | Create PR with conventional naming |
| update | `/update` or `jj-update` | Update existing PR |
| sync | `/sync` or `jj-sync` | Sync with main branch |
| ci-watch | `watch-ci-jobs` | Monitor CI (standalone tool) |

## Testing

Preview the workflow without making changes:
```bash
jj-finish --dry-run
```

Run individual steps with --dry-run:
```bash
jj-push --dry-run
jj-pr --dry-run
```
