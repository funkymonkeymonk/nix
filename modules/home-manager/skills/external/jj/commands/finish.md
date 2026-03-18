---
description: Push changes, create PR, watch CI, and optionally merge
agent: build
---

Run the jj-finish workflow for the current branch:

1. Push all changes to origin
2. Create a PR if one doesn't exist  
3. Watch for all CI checks to complete
4. If checks fail: I'll fix the issues and retry (up to 5 times)
5. If checks pass: ask if you want to merge

Use the jj skill for reference. The script is at `jj-finish` in PATH.

Run: `jj-finish $ARGUMENTS`

If no arguments provided, run with defaults. Common arguments:
- `--merge` - Prompt to merge on success
- `--max-retries N` - Limit retry attempts
