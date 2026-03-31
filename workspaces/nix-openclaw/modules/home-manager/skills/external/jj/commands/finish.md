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
4. **[pr-merge skill]** - Merge PR (if --merge specified)

## Usage

```bash
jj-finish [--merge] [--max-retries N] [--dry-run]
```

## Options

- `--merge` - Prompt to merge on CI success
- `--max-retries N` - Maximum retry attempts on failure (default: 5)
- `--dry-run` - Show what would be done without executing

## Examples

```bash
jj-finish              # Push, create PR, watch CI
jj-finish --merge      # Also prompt to merge on success
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
| pr-merge | `/pr-merge` or `jj-pr-merge` | Merge PR |

## Testing

Preview the workflow without making changes:
```bash
jj-finish --dry-run
```

Run individual steps with --dry-run:
```bash
jj-push --dry-run
jj-pr --dry-run
jj-pr-merge --dry-run
```
