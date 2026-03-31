---
description: Push bookmark to origin
agent: build
---

Push bookmark changes to origin (GitHub).

## Overview

Standalone push command. Can be used independently or as part of the finish workflow.

## Usage

```bash
jj-push [--allow-new] [--dry-run] [bookmark]
```

## Options

- `--allow-new` - Allow pushing a new bookmark for the first time
- `--dry-run` - Show what would be done without executing
- `[bookmark]` - Bookmark to push (defaults to current bookmark)

## Examples

```bash
jj-push                    # Push current bookmark
jj-push feat/my-feature    # Push specific bookmark  
jj-push --allow-new        # Push new bookmark for first time
jj-push --dry-run          # Preview push
```

## Related

- Use `/finish` for full workflow (includes push)
- Use `/pr` to create PR after pushing
