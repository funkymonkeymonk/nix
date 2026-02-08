---
description: Open PR review dashboard (gh-dash) in a new zellij pane
---

# /pr-review

Opens the gh-dash PR review dashboard in a new zellij pane within the current session.

## Usage

```
/pr-review [PR_NUMBER]
```

## Arguments

- `PR_NUMBER` (optional): If provided, the dashboard will focus on this PR

## Implementation

Run this command to open gh-dash in a new pane:

```bash
zellij run -- gh-dash --config "$(pwd)/configs/ide/gh-dash.yml"
```

If a PR number is provided, you can also show its status inline first:

```bash
gh pr view $1
```

Then open the dashboard for detailed review.

## Notes

- **Important**: Run from a terminal pane in zellij, not directly from opencode (zellij actions don't work from subprocesses)
- Requires zellij session (works within `task ide`)
- Uses project-specific gh-dash config from `configs/ide/gh-dash.yml`
- Dashboard shows: CI status, review status, merge readiness

## Alternative: Inline PR Status

If you can't open a new pane, use these commands to check PR status inline:

```bash
# View PR details
gh pr view <PR_NUMBER>

# Check CI status
gh pr checks <PR_NUMBER>

# List your PRs with status
gh pr list --author @me --json number,title,state,statusCheckRollup
```
