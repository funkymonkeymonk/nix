---
title: "Multi-Agent Development with jj Workspaces"
description: "How Jujutsu workspaces isolate concurrent changes and interact with Nix flakes"
type: explanation
audience: developer
last-reviewed: 2026-11-11
---

# Multi-Agent Development with jj Workspaces

Jujutsu workspaces let multiple agents or developers work in separate working
copies of one repository. Each workspace has its own working copy while sharing
the repository's commit graph.

## Why workspaces help

Separate working copies prevent concurrent changes from colliding in the same
files. Each agent can describe changes and use a separate bookmark. This makes
parallel work easier to review and integrate.

Use the native `jj workspace` commands. The Nix flake no longer installs the
former `jj-workspace` helper or the `jj` skill's bundled PR and sync wrappers.
See [Use Jujutsu Workspaces](../how-to/use-workspaces.md) for workspace
commands and [Create a PR with jj](../how-to/create-pr-with-jj.md) for the
native bookmark and PR workflow.

## Workspaces and Nix flakes

Nix flake commands evaluate repository files through Git. In this colocated
Jujutsu repository, track new files and describe changes before final Nix
evaluation. This prevents evaluation from missing new files.

The workspace-aware `s` and `switch` functions run machine tasks from the
repository root. They keep flake commands anchored to the correct project
while the user works in a workspace.

## Coordinating parallel work

Give each workspace a clear name. Assign a separate task and bookmark to each
agent. Use the shared task tracker to prevent duplicate work, then review and
merge each change through its own PR. The [Yaks + JJ Workspaces
guide](yaks-workspaces.md) explains how to coordinate tasks across agents.

For Nix validation steps, see [the JJ workflow](../how-to/jj-workflow.md).
