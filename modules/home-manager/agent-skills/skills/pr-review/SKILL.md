---
name: pr-review
description: "Use when checking PR status, reviewing CI results, or preparing to merge PRs. Provides CLI commands for quick checks and TUI dashboard for comprehensive review."
---

# PR Review Workflow

## Overview

This skill teaches you how to check PR status, review CI results, and prepare PRs for merging using `gh` CLI commands and the `gh-dash` TUI dashboard.

## Quick CLI Commands

For quick status checks without leaving the current context:

### Check a specific PR

```bash
# View PR details (status, reviews, checks)
gh pr view <PR_NUMBER>

# Check CI status only
gh pr checks <PR_NUMBER>

# View PR diff
gh pr diff <PR_NUMBER>
```

### List PRs

```bash
# Your open PRs
gh pr list --author @me

# PRs awaiting your review
gh pr list --search "review-requested:@me"

# PRs ready to merge (all checks passed)
gh pr list --author @me --json number,title,mergeable,reviewDecision,statusCheckRollup
```

### Merge a PR

```bash
# Merge with squash (recommended)
gh pr merge <PR_NUMBER> --squash

# Auto-merge when checks pass
gh pr merge <PR_NUMBER> --auto --squash
```

## TUI Dashboard

For comprehensive PR review with visual interface, use the `/pr-review` slash command to open `gh-dash` in a new zellij pane.

The dashboard shows:
- CI status for each PR
- Review status (approved, changes requested, pending)
- Time since last update
- PR title and repo

### Dashboard Keybindings

| Key | Action |
|-----|--------|
| `j/k` | Navigate up/down |
| `Enter` | View PR details |
| `c` | Checkout PR branch |
| `d` | View diff |
| `v` | Open in browser |
| `m` | Merge PR |
| `r` | Refresh |
| `q` | Quit |

## When to Use What

| Scenario | Use |
|----------|-----|
| Quick check if CI passed | `gh pr checks <PR>` |
| See if PR is ready to merge | `gh pr view <PR>` |
| Review multiple PRs | `/pr-review` (dashboard) |
| Deep dive into a PR | `/pr-review` then navigate |
| Merge a single PR | `gh pr merge <PR> --squash` |

## Integration with task ide

When using `task ide`, you can:

1. **Standard mode**: `task ide` - Files + Agent only
2. **With PR pane**: `WITH_PR=1 task ide` - Files + Agent + gh-dash

The PR pane stays visible while you work, showing real-time updates.

## Standalone Dashboard

Run `task pr:review` or `task pr` to launch gh-dash in a dedicated zellij session.
