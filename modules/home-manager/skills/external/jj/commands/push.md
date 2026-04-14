---
description: Push bookmark to origin
agent: build
---

Push bookmark changes to origin (GitHub).

## Overview

Standalone push command. Can be used independently or as part of the finish workflow.

## Usage

```bash
jj-push [--dry-run] [bookmark]
```

## Options

- `--dry-run` - Show what would be done without executing
- `[bookmark]` - Bookmark to push (defaults to current bookmark)

## Examples

```bash
jj-push                    # Push current bookmark
jj-push feat/my-feature    # Push specific bookmark
jj-push --dry-run          # Preview push
```

## Related

- Use `/finish` for full workflow (includes push)
- Use `/pr` to create PR after pushing
