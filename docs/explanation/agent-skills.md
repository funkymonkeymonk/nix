---
title: "Agent Skills System"
description: "How the Nix flake sources and deploys agent skills"
type: explanation
audience: agent
last-reviewed: 2026-11-11
---

# Agent Skills System

The public `funkymonkeymonk/skills` repository is the source of standalone agent
skills for this Nix configuration. It stores each skill as a directory with a
`SKILL.md` file and any supporting files.

The Nix flake consumes that repository as a raw, non-flake input. The flake
lock records the exact revision, so every build uses the same skill content.
A change in the skills repository does not affect a machine until the Nix
repository updates its lock file and rebuilds.

## Deployment model

Home Manager discovers every directory under the input's `skills/` path that
contains `SKILL.md`. It links the complete directory to `~/.agents/skills/`.
OpenCode and Pi discover this shared location. Claude Code receives the same
skill directories through its Home Manager module.

The Nix manifest stores optional agent metadata. It does not contain skill
content or select which repository skills are installed. Machines with an enabled `developer`, `creative`, `workstation`, `opencode`,
`claude`, or `pi` role receive all skills from the pinned input.

## Tradeoffs

A single source repository avoids copied skill files and activation-time
network fetches. Nix builds use the locked input and install its complete
content from the store.

All machines that use this flake receive the same skill set. Per-machine skill
selection is not supported. The public source and system closure can also make
skill content publicly available through configured binary caches.

For update steps, see [Update or add a skill](../how-to/add-skill.md). For the
input and install locations, see the [Skills reference](../reference/skills.md).
