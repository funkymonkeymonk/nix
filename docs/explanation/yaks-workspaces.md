# Yaks and JJ Workspaces

> For a hands-on introduction, see the [tutorial](../tutorials/yak-shaving.md). For command details, see the [reference](../reference/yaks.md).

## Why Yaks + JJ Workspaces?

This repository combines two tools that solve different problems:

- **yx (yaks)** tracks _what_ needs doing -- a shared tree of tasks stored in hidden git refs
- **jj workspaces** provide _where_ to do it -- isolated working copies that share the same repository

Together they enable multiple agents (or humans) to work on different tasks simultaneously without stepping on each other.

## How Yaks Data Is Shared

Yaks stores its events in `refs/notes/yaks`, a hidden git ref separate from your branches. When you run `yx sync`, it pushes and pulls this ref -- independent of whatever branch you're on.

Because all jj workspaces in this repository point to the same underlying `.git` directory, they all see the same yaks data. An agent in `.workspaces/feat-auth/` and another in `.workspaces/fix-ci/` both operate on the same yak map.

This is a deliberate design choice: yaks represent project-wide goals, not workspace-local tasks. A single source of truth prevents work from being duplicated or lost when workspaces are created and destroyed.

## The CRDT Advantage

Traditional TODO lists break when two people edit simultaneously -- you get merge conflicts or lost updates. Yaks avoids this entirely through operation-based CRDTs (Conflict-free Replicated Data Types).

Every change (add, rename, state change, context update) is recorded as an immutable event. Events from different sources merge deterministically regardless of order. Two agents can claim different yaks, add context, and mark work done -- all without coordination. The next `yx sync` merges everything cleanly.

This matters for multi-agent workflows where agents operate independently in their own workspaces and may not be online at the same time.

## Workspace Isolation vs. Shared State

There's an intentional asymmetry:

- **Code** is isolated per workspace. Each jj workspace has its own working copy at its own commit. Changes in one workspace don't appear in another until merged.
- **Yaks** are shared across all workspaces. Claiming a yak in one workspace is visible from every other workspace after sync.

This means the yak map serves as the coordination layer. Agents check what's claimed (`wip`) before starting work, and mark tasks done when finished. The code stays isolated; the task state stays shared.

## The Claim Protocol

Without a claim protocol, two agents could start the same yak simultaneously. The protocol is:

1. Sync to get latest state
2. Check if the yak is already `wip`
3. Claim it with `yx start`
4. Sync again to publish the claim

This isn't a lock -- CRDTs don't support locks. It's a convention. If two agents claim the same yak in the same sync window (before either syncs), both will see `wip` on the next sync and one should back off. In practice, with 5-minute sync intervals, collisions are rare.

## Why Not Per-Workspace Yaks?

An alternative design would give each workspace its own isolated yak map (separate git repos). This would prevent any possibility of collision but creates worse problems:

- Tasks completed in one workspace aren't visible elsewhere
- No single view of project progress
- Work gets duplicated when agents can't see each other's claims
- Cleanup requires visiting each workspace

The shared model trades a small collision risk for much better visibility and coordination.
