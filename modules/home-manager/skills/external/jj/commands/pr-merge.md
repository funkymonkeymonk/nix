---
description: Merge a pull request
agent: build
---

Merge a pull request with configurable merge method.

## Overview

Standalone merge command. Can be used independently or as part of the finish workflow.

## Usage

```bash
jj-pr-merge [--method squash|merge|rebase] [--auto] [--dry-run] [branch]
```

## Options

- `--method METHOD` - Merge method: squash (default), merge, or rebase
- `--auto` - Configure auto-merge instead of merging immediately
- `--dry-run` - Show what would be done without executing
- `[branch]` - Branch to merge (defaults to current bookmark)

## Examples

```bash
jj-pr-merge                    # Merge current branch with squash
jj-pr-merge feat/my-feature    # Merge specific branch
jj-pr-merge --method rebase    # Use rebase merge
jj-pr-merge --auto             # Configure auto-merge
jj-pr-merge --dry-run          # Preview merge
```

## Related

- Use `/finish --merge` for full workflow (includes merge)
- Use after CI passes to complete PR
