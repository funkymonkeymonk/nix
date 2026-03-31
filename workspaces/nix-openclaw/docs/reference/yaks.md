# Yaks - Distributed TODO Lists

## What is Yaks?

Yaks (`yx`) is a **distributed TODO list** designed for teams of humans and AI agents. It uses a CRDT (Conflict-free Replicated Data Type) approach stored in hidden git refs, enabling **zero-conflict collaboration**.

## Key Concepts

- **Everything is a "Yak"** - A simple tree structure (no epics/stories/tasks hierarchy)
- **Three States** - `todo`, `wip`, `done`
- **Event-Sourced** - All changes stored as immutable events on `.refs/yaks`
- **Conflict-Free** - Multiple agents can edit simultaneously without coordination

## Quick Start

### Basic Commands

```bash
# Add a new yak
yx add "Fix authentication bug"

# Add a sub-yak (yak shaving!)
yx add "Update database schema" --under "Fix authentication bug"

# Mark as in-progress
yx state "Fix authentication bug" wip

# Add context/notes
echo "Need to handle edge case with OAuth" | yx context "Fix authentication bug"

# Mark complete
yx done "Fix authentication bug"

# View the yak map
yx ls

# Sync with remote (uses hidden git ref)
yx sync
```

### Useful Aliases (Pre-configured)

| Alias | Command | Description |
|-------|---------|-------------|
| `yl` | `yx ls` | List yaks |
| `yla` | `yx ls --all` | List all yaks including done |
| `ya` | `yx add` | Add a yak |
| `yd` | `yx done` | Mark yak done |
| `ys` | `yx sync` | Sync with remote |

## For AI Agents

```bash
# Discover work (JSON output)
yx ls --format json

# Claim a yak
yx state "fix the bug" wip

# Store progress notes
echo "Refactored auth module" | yx field "fix the bug" progress

# Complete work
yx done "fix the bug"

# Always sync when done
yx sync
```

## How It Works

```
┌─────────────────────────────────────┐
│  Git Repository                     │
│  ├── .refs/yaks (hidden ref)        │
│  │   └── Event log (CRDT)           │
│  └── Your code                      │
└─────────────────────────────────────┘
         ↓
┌─────────────────────────────────────┐
│  yx CLI reads events                │
│  └── Builds current state           │
└─────────────────────────────────────┘
```

### The CRDT Magic

Unlike traditional TODO lists that might have:
- Lock files
- Merge conflicts
- "Someone else is editing" errors

Yaks uses **operation-based CRDTs**:
1. Every change is an immutable event
2. Events from different sources merge naturally
3. Final state is deterministic regardless of merge order
4. Works offline, syncs when connected

## Yakthang (Orchestration Layer)

Yakthang builds on Yaks to create a full autonomous workspace:

- **Yakob** - Orchestrator agent (Claude) that plans work
- **Yak Shavers** - Worker agents in separate Zellij tabs
- **YakMap** - Visual Zellij plugin showing real-time task status

See: https://github.com/wellmaintained/yakthang

## Integration in Your Nix Config

The `yaks` package is now:
- ✅ Added to the `developer` role in `bundles.nix`
- ✅ Available as a shell alias (`yl`, `ya`, `yd`, `ys`)
- ✅ Buildable via `nix build .#yaks`

To apply to your system:
```bash
s  # or: devenv tasks run system:switch
```

## Next Steps

1. **Try it out** in any git repository:
   ```bash
   cd ~/some-project
   yx add "Explore yaks tool"
   yx ls
   ```

2. **Add to a project's AGENTS.md**:
   ```markdown
   ## Task Management with Yaks

   This project uses [yaks](https://github.com/mattwynne/yaks) for task tracking.

   - Discover work: `yx ls --format json`
   - Claim a yak: `yx state "task name" wip`
   - Add context: `echo "notes" | yx context "task name"`
   - Mark done: `yx done "task name"`
   - Sync: `yx sync`
   ```

3. **Consider Yakthang** if you want full orchestration with Zellij

## Resources

- **Yaks**: https://github.com/mattwynne/yaks
- **Yakthang**: https://github.com/wellmaintained/yakthang
- **CRDTs**: https://crdt.tech/
