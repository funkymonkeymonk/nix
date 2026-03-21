# Yaks Setup in JJ Workspaces

## Architecture

This repository uses **Jujutsu (jj) workspaces** with **colocated git** for yaks integration.

### Directory Structure

```
~/src/funkymonkeymonk/nix/          # Parent jj repo with colocated git
├── .git/                            # Shared git repository
├── .gitignore                       # Contains .yaks/ exclusion
└── .jj/                             # JJ repository data

~/workspaces/
├── nix-yak-shaving/                 # This workspace
│   ├── .git -> ~/src/.../nix/.git   # Symlink to parent git
│   ├── .jj/repo -> ../../../src/... # JJ workspace config
│   └── .yaks/                       # Yaks working directory
├── nix-openclaw/                    # Other workspaces...
└── ...
```

### Important: Shared Yaks Data

**All jj workspaces share the same yaks data** because they use the same underlying git repository. This means:

✅ **Pros:**
- Single source of truth across all workspaces
- Can see all project tasks from any workspace
- Natural for project-wide task tracking

⚠️ **Considerations:**
- Use **workspace-specific prefixes** to avoid naming conflicts:
  - `nix-yak-shaving: Fix flake.nix`
  - `nix-openclaw: Update API endpoints`
  - `default: Refactor common modules`

## Setup Required for Each New Workspace

When creating a new workspace that needs yaks:

```bash
# In the new workspace directory
cd ~/workspaces/nix-new-workspace

# Create symlink to parent git repo
ln -s ~/src/funkymonkeymonk/nix/.git .git

# Yaks is now available
yx ls
yx add "nix-new-workspace: My task"
```

## Alternative: Per-Workspace Isolation

If you prefer **isolated yaks per workspace** (not currently implemented):

1. Initialize a separate git repo in the workspace:
   ```bash
   git init
   echo ".yaks/" >> .gitignore
   ```

2. Yaks will use this local repo instead of the parent

3. **Trade-off:** Tasks won't be visible across workspaces

## Current Yaks in This Repository

```
● nix-yak-shaving: Review yaks integration and documentation
├─ ○ nix-yak-shaving: Try yaks in daily workflow
╰─ ○ nix-yak-shaving: Update AGENTS.md with yaks guidelines
```

## Quick Reference

| Command | Description |
|---------|-------------|
| `yx ls` or `yl` | List all yaks (shared across workspaces!) |
| `yx add "prefix: Task"` or `ya "prefix: Task"` | Add workspace-prefixed yak |
| `ya "Task" --under "Parent"` | Add child yak |
| `yx state "Task" wip` | Mark in-progress |
| `yd "Task"` | Mark done |
| `ys` | Sync with remote |

## Files Modified

- `~/.gitignore` - Added `.yaks/` exclusion (in parent repo)
- `~/workspaces/nix-yak-shaving/.git` - Symlink to parent git repo
