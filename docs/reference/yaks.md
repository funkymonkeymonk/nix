# Yaks Reference

Yaks (`yx`) is a distributed, CRDT-based TODO list stored in hidden git refs (`refs/notes/yaks`). It organizes work as a DAG/tree with three states: `todo`, `wip`, `done`.

> **New to yaks?** See the [tutorial](../tutorials/yak-shaving.md). For architecture details, see [Yaks + JJ Workspaces](../explanation/yaks-workspaces.md).

## Commands

| Command | Description |
|---------|-------------|
| `yx add "name"` | Add a new yak |
| `yx add "name" --under "parent"` | Add a child yak (parent is blocked by child) |
| `yx ls` | Show the yak tree (todo + wip only) |
| `yx ls --all` | Show all yaks including done |
| `yx ls --format json` | JSON output for programmatic use |
| `yx ls --only todo` | Filter by state |
| `yx show "name"` | Show yak details |
| `yx show "name" --format json` | Show details as JSON |
| `yx start "name"` | Set state to wip |
| `yx state "name" <state>` | Set arbitrary state (todo, wip, done) |
| `yx done "name"` | Mark as done (requires all children done) |
| `yx context "name"` | Set context from stdin |
| `yx context --show "name"` | Read context |
| `yx field "name" <field>` | Set custom field from stdin |
| `yx field --show "name" <field>` | Read custom field |
| `yx tag "name" <tag>` | Add a tag |
| `yx tag "name" --remove <tag>` | Remove a tag |
| `yx move "name" --under "parent"` | Move yak under a parent |
| `yx move "name" --to-root` | Move yak to root level |
| `yx rename "old" "new"` | Rename a yak |
| `yx rm "name"` | Remove a yak |
| `yx prune` | Remove all done yaks |
| `yx sync` | Sync with remote via hidden git ref |
| `yx log` | Show event log |
| `yx compact` | Compact event stream into snapshot |
| `yx reset` | Rebuild from git event store |

## Shell Aliases

| Alias | Expands To |
|-------|------------|
| `yl` | `yx ls` |
| `yla` | `yx ls --all` |
| `ya` | `yx add` |
| `yd` | `yx done` |
| `ys` | `yx sync` |

## Tree Semantics

- **Children block parents**: A parent cannot be marked done until all children are done
- **Nesting = dependency**: Adding a child under a parent means "parent is blocked by child"
- **Work leaves first**: Leaf nodes (no children) are unblocked and ready to implement
- **Bidirectional growth**: Add children downward (discover blockers) or create parents upward (discover broader goals with `yx move`)

## States

| State | Meaning |
|-------|---------|
| `todo` | Not started |
| `wip` | In progress (claimed by someone) |
| `done` | Complete |

## Storage

- Events stored in `refs/notes/yaks` (hidden git ref)
- Working directory cached in `.yaks/` (gitignored)
- Operation-based CRDTs -- changes merge without conflicts regardless of order
- `yx sync` pushes/pulls the hidden ref

## Conventions

| Convention | Description |
|------------|-------------|
| `@needs-human` tag | Yak is blocked on a human decision |
| `progress` field | Store implementation progress notes |
| Claim protocol | `yx sync` -> `yx show` -> `yx start` -> `yx sync` |

## Installation

Included in the `developer` role. Available after `devenv tasks run system:switch`.

## Resources

- Upstream: https://github.com/mattwynne/yaks
- Yakthang orchestration: https://github.com/wellmaintained/yakthang
- CRDT background: https://crdt.tech/
