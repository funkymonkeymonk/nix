# Agent Skills System

This document explains how the AI agent skills system works and why it's designed this way.

## The Problem

AI coding assistants (OpenCode, Claude Code) support "skills" - markdown files that provide domain-specific instructions. Managing these skills manually across multiple machines is tedious:

- Skills need to be in specific directories
- Different machines might need different skills
- Keeping skills updated is error-prone
- Skills may depend on other skills

## The Solution

This configuration manages skills through Nix:

1. **Skills are defined in the repository** - Version controlled and reviewable
2. **Skills are assigned to roles** - Developers get developer skills, etc.
3. **Nix handles installation** - Skills are symlinked to the correct location
4. **Updates require a rebuild** - Intentional change management

## How It Works

### Skill Sources

Skills come from three places:

```
modules/home-manager/skills/
├── internal/        # Skills written for this repo
├── external/        # Skills adapted from other sources
└── (superpowers)    # Skills from the superpowers flake input
```

### The Manifest

`manifest.nix` defines all available skills:

```nix
"debugging" = {
  description = "Systematic debugging approach";
  roles = ["developer"];
  source = {
    type = "internal";
    path = ./internal/debugging;
  };
  deps = [];
};
```

Each skill has:
- **description**: What the skill does
- **roles**: Which roles include this skill
- **source**: Where the skill content lives
- **deps**: Other skills this depends on

### Role-Based Installation

When you enable roles in your machine config:

```nix
roles = ["developer" "creative"]
```

The system:
1. Looks up which skills those roles include
2. Resolves any skill dependencies
3. Creates symlinks via home-manager

### Installation Location

Skills are installed to:

```
~/.config/opencode/skills/<skill-name>/SKILL.md
```

This is the standard location OpenCode expects.

## Design Decisions

### Why Nix, Not a Script?

**Immutability**: Skills in the Nix store can't be accidentally modified. Changes require an explicit rebuild.

**Reproducibility**: Every machine with the same roles gets the exact same skills.

**Rollback**: If a skill update breaks something, `nix profile rollback` restores the previous version.

### Why Role-Based?

Not everyone needs all skills:

- A gaming machine doesn't need "debugging" skills
- A creative workstation might not need "tdd" skills
- Work machines might have different skills than personal ones

Roles let you customize without maintaining per-machine skill lists.

### Why Dependencies?

Some skills build on others. The "verification-before-completion" skill assumes you understand debugging. Dependencies ensure prerequisites are always available.

## Comparison to Manual Management

| Aspect | Manual | Nix-Managed |
|--------|--------|-------------|
| Installation | Copy files | Automatic on rebuild |
| Updates | Manual per machine | One rebuild |
| Consistency | Easy to drift | Guaranteed |
| Rollback | Hope you have backups | Built-in |
| Per-machine customization | Manual | Via roles |

## The Superpowers Input

The flake includes an input called `superpowers`:

```nix
superpowers.url = "github:obra/superpowers";
```

This provides community-maintained skills. The manifest can reference these:

```nix
source = {
  type = "superpowers";
  path = "skills/some-skill";
};
```

This allows using upstream skills while still controlling which ones are installed.

## Tradeoffs

### Requires Rebuild for Changes

**Pro**: Changes are intentional and tracked
**Con**: Can't quickly test a skill modification

Workaround: Edit the skill directly in `~/.config/opencode/skills/` for testing, then port changes back to the repo.

### All-or-Nothing per Role

**Pro**: Simple mental model
**Con**: Can't easily exclude one skill from a role

Workaround: Create a custom role, or modify the manifest to use more granular roles.

### Symlinks, Not Copies

**Pro**: Updates are atomic
**Con**: Some tools might not follow symlinks properly

This hasn't been an issue with OpenCode or Claude Code.
