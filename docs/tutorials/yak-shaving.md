# Your First Yak: Task Tracking with yx

In this tutorial, you'll learn how to use `yx` (yaks) to track work as a tree of nested goals. By the end, you'll have created a yak map, worked through a task, and synced your changes.

## What You'll Learn

- How to add and organize yaks
- How nesting represents dependencies
- How to claim, implement, and complete a yak
- How to sync with teammates

## Prerequisites

- A machine with this Nix configuration applied (see [Getting Started](getting-started.md))
- A git repository to work in (this repo works fine)
- About 15 minutes

## Step 1: Check That yx Is Available

Open a terminal in any git repository managed by this Nix config:

```bash
yx --version
```

You should see `yx 0.1.0` or similar. If not, make sure the `developer` role is enabled in your target configuration.

## Step 2: See What's Already There

```bash
yx ls
```

This shows the current yak map -- a tree of tasks. If the repository is new to yaks, this will be empty. If you're in the nix config repo, you'll see existing tasks organized by priority.

## Step 3: Add Your First Yak

Let's add a simple goal:

```bash
yx add "Learn how yaks work"
```

Now check the map:

```bash
yx ls
```

You should see your new yak in the tree with a `todo` state.

## Step 4: Discover a Blocker

Yak mapping is about approaching a goal and finding what blocks you. Let's say to learn yaks, we first need to try the basic commands:

```bash
yx add "Try basic yx commands" --under "Learn how yaks work"
```

Check the map again:

```bash
yx ls
```

Notice the nesting: "Learn how yaks work" now has a child. This means the parent is **blocked by** the child -- you can't mark the parent done until the child is complete.

## Step 5: Add Context

Add notes to help yourself (or another agent) understand the task:

```bash
cat <<'EOF' | yx context "Try basic yx commands"
# Goal
Practice add, done, sync, and context commands.

# Definition of Done
- Added at least 3 yaks
- Completed at least 1
- Synced with remote
EOF
```

Read it back:

```bash
yx context --show "Try basic yx commands"
```

## Step 6: Claim the Yak

Before starting work, claim it so others know it's taken:

```bash
yx start "Try basic yx commands"
```

Check the map -- the state should now show `wip`:

```bash
yx ls
```

## Step 7: Do the Work

Let's add a couple more yaks to practice:

```bash
yx add "Read the yaks README"
yx ls
yx add "Try syncing with remote"
yx ls
```

Now complete the one you just read:

```bash
yx done "Read the yaks README"
yx ls
```

Notice the done yak disappears from the default view. To see it:

```bash
yx ls --all
```

## Step 8: Sync with the Remote

Syncing pushes your yak changes to the shared git ref so teammates and other agents can see them:

```bash
yx sync
```

This uses a hidden git ref (`refs/notes/yaks`), not your regular branches. It won't affect your code commits.

## Step 9: Complete the Chain

Finish the remaining tasks:

```bash
yx done "Try syncing with remote"
yx done "Try basic yx commands"
```

Now try to complete the parent:

```bash
yx done "Learn how yaks work"
```

This works because all children are done. If any child were still incomplete, yaks would block you.

## Step 10: Clean Up

Remove completed yaks from the event log:

```bash
yx prune
yx sync
```

## What You've Learned

- Yaks are organized as a tree where **children block parents**
- You work **leaves first** (deepest nodes), then their parents
- `yx sync` shares state with teammates via hidden git refs
- Context and custom fields attach notes to yaks
- The CRDT merge means multiple people can edit simultaneously without conflicts

## What's Next

- **Coordinate with agents**: Read [Yaks + JJ Workspaces](../explanation/yaks-workspaces.md) to understand how multiple agents share yaks across workspaces
- **Full command reference**: See [Yaks Reference](../reference/yaks.md) for all commands and options
- **Use the skill**: The `yak-shaving` skill teaches agents how to use yx with jj workspaces -- see [Skills Reference](../reference/skills.md)
