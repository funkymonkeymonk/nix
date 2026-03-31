# PR Review Workflow Design

**Date**: 2026-02-07  
**Status**: Approved  

## Overview

Add a terminal-based PR review workflow using `gh-dash` that integrates with the existing `task ide` tooling and enables agent-triggered PR review via skills and slash commands.

## Goals

1. Check PR status before merging (CI status, merge readiness)
2. View review comments and feedback
3. Integrate with existing `task ide` workflow
4. Enable agent to trigger PR review programmatically

## Solution

Use **gh-dash** - a rich terminal UI for GitHub (10k+ stars, actively maintained, available in nixpkgs).

### Features of gh-dash
- TUI dashboard showing PRs with CI status and review status
- Vim-style keybindings
- Configurable via YAML
- Works as a `gh` CLI extension

## Architecture

### IDE Layout (with PR pane enabled)

```
┌─────────────────────────────────────────────────────────┐
│ task ide (WITH_PR=1)                                    │
├──────────────┬──────────────────┬──────────────────────┤
│    files     │      agent       │      gh-dash         │
│   (yazi)     │   (opencode)     │  (PR dashboard)      │
│     30%      │       40%        │        30%           │
└──────────────┴──────────────────┴──────────────────────┘
```

### Usage Modes

1. **`task pr:review`** - Standalone gh-dash in dedicated zellij session
2. **`WITH_PR=1 task ide`** - IDE with gh-dash pane on the right
3. **`/pr-review` slash command** - Agent opens gh-dash in new zellij pane
4. **`pr-review` skill** - Agent knowledge for CLI-based PR checks

## Implementation

### Files to Create/Modify

| File | Change |
|------|--------|
| `bundles.nix` | Add `gh-dash` to `developer` role packages |
| `devenv.nix` | Add `gh-dash` to development environment |
| `configs/ide/layout.kdl.template` | Update proportions (30/67 -> 30/70) |
| `configs/ide/layout-with-pr.kdl.template` | **New** - 3-pane layout |
| `configs/ide/gh-dash.yml` | **New** - gh-dash configuration |
| `Taskfile.yml` | Modify `ide` task, add `pr:review` task |
| `modules/home-manager/agent-skills/skills/pr-review/` | **New** - Personal skill |
| `.opencode/commands/pr-review.md` | **New** - Slash command |

### gh-dash Configuration

```yaml
prSections:
  - title: My PRs
    filters: author:@me
  - title: Review Requested  
    filters: review-requested:@me

defaults:
  prsLimit: 20
  preview:
    open: true
    width: 60
```

### Skill Contents

The `pr-review` skill teaches the agent:
- How to check PR status: `gh pr view`, `gh pr checks`
- How to list PRs: `gh pr list --author @me`
- When to use CLI vs UI (quick checks vs deep review)
- How to trigger the slash command for visual review

### Slash Command Behavior

`/pr-review [PR_NUMBER]`:
- Opens gh-dash in a new zellij pane via `zellij run`
- Optional PR number argument for direct navigation
- Works within existing zellij session

## Package Availability

- **nixpkgs**: `gh-dash` version 4.22.0
- **Installation**: Via `developer` bundle + devenv

## Success Criteria

1. `task pr:review` launches gh-dash dashboard
2. `WITH_PR=1 task ide` shows 3-pane layout with gh-dash
3. Agent can use `/pr-review` to open dashboard
4. Agent can use CLI commands to check PR status inline
