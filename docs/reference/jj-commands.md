---
title: "JJ Commands Reference"
description: "Complete reference for jj commands and aliases"
type: reference
---

# JJ Commands Reference

## Core Commands

| Command | Description | Example |
|---------|-------------|---------|
| `jj new` | Create new empty commit | `jj new` |
| `jj status` | Show working copy status | `jj status` |
| `jj describe -m "msg"` | Set commit message | `jj describe -m "feat: add X"` |
| `jj diff` | Show changes | `jj diff` |
| `jj bookmark set <name> -r @` | Create bookmark | `jj bookmark set feat/x -r @` |
| `jj git push --bookmark <name>` | Push bookmark | `jj git push --bookmark feat/x --allow-new` |
| `jj squash` | Fold changes into parent | `jj squash` |
| `jj ba` | Alias for `jj bookmark advance` | `jj ba feat/x` |

## Editor

Helix (`hx`) is configured as the default editor.
