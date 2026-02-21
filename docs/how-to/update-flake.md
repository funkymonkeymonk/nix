# How to Update Flake Dependencies

This guide shows you how to update your Nix flake dependencies.

## Manual Update

### Update All Inputs

```bash
devenv tasks run flake:update
```

This updates `flake.lock` with the latest versions of all inputs.

### Apply Updates

```bash
devenv tasks run switch
```

### Validate Before Applying

```bash
devenv tasks run test:full
```

## Automatic Weekly Updates

The repository includes a GitHub Action that automatically:
- Updates flake.lock every Friday at 4:00 AM UTC
- Creates a PR with the changes
- Applies automated fixes for common package renames
- Closes the previous week's update PR

### Reviewing Update PRs

Update PRs include:
- Executive summary of changes
- Technical details of package updates
- List of automated fixes applied
- Validation results

### Manual Trigger

Trigger the update workflow manually:

```bash
gh workflow run "Weekly Flake Update"
```

## Rollback

If an update causes issues:

```bash
git checkout main
git reset --hard HEAD~1
devenv tasks run switch
```

Or revert to a specific flake.lock:

```bash
git checkout <commit-hash> -- flake.lock
devenv tasks run switch
```
