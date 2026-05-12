---
description: Create a stacked PR on top of the current branch
agent: build
---

Create a stacked PR whose base is the current branch. Same immutable
commit-on-top model as `/pr`.

See the `jj` skill (SKILL.md) for the full design.

## Prerequisites

The current `@` should be a commit containing the stack-level changes, with
its parent (`@-`) being a commit that carries the parent branch's bookmark
(usually the tip of the PR below you in the stack).

Typical flow:
```bash
# You've just finished and pushed the parent PR (e.g. feat/api):
jj new                 # Start new work on top
# ... make stack-level changes, maybe several local commits ...
/stack feat api-ui --message "feat: add UI for new API"
```

## What you must do before calling the script

1. **Generate a conventional-commit message** describing this stack level's
   changes.
2. Decide type (feat/fix/hotfix/release/chore) and a kebab-case description.
3. Run: `jj-stack <type> <description> --message "<your message>"`

## After success

**Always run `jj new`** before making more changes.

## If no parent bookmark is found

The parent commit needs a bookmark. Either:
- Make sure you branched from a commit with a bookmark (the previous PR's tip), OR
- Set one manually: `jj bookmark set <parent-branch-name> -r @-`
