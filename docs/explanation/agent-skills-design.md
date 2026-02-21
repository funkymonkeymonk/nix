# Agent Skills Design

This document explains the design decisions behind the agent skills management system.

## Problem Statement

AI coding assistants benefit from consistent, reusable guidance for common tasks. Without a structured system:
- Each conversation starts from scratch
- Best practices aren't codified
- Different machines have different skills available

## Design Goals

1. **Declarative**: Skills managed through Nix, not manual installation
2. **Role-based**: Skills match user needs automatically
3. **Discoverable**: Users find relevant skills through their roles
4. **Extensible**: Easy to add custom skills

## Architecture Decisions

### Why Nix-Managed Skills?

**Alternative**: Manual installation with shell scripts

**Why Nix**: 
- Reproducible across machines
- Atomic updates (all or nothing)
- Rollback capability
- Integration with existing configuration

### Why Role-Based Assignment?

**Alternative**: Install all skills everywhere

**Why roles**:
- Reduces noise (developers don't need creative skills by default)
- Progressive discovery (adding a role reveals new capabilities)
- Smaller installation footprint

### Why Symlinks from Nix Store?

**Alternative**: Copy files to home directory

**Why symlinks**:
- Immutable (can't accidentally modify installed skills)
- Atomic updates during rebuild
- Easy rollback (previous generation still exists)
- No drift between declared and actual state

## Skill Format

Skills follow the Agent Skills specification:

```markdown
---
name: skill-name
description: Brief description
---

# Skill Content
```

The frontmatter enables:
- Automatic indexing
- Validation
- Tool integration

## Role Assignment

Skills are assigned to roles in the manifest:

```nix
"debugging" = {
  roles = ["developer"];
  ...
};
```

This creates a many-to-many relationship:
- One skill can apply to multiple roles
- One role can have multiple skills

## Progressive Discovery

Users discover skills by enabling roles:

```
Enable "developer" role → debugging, tdd, writing-plans skills appear
Enable "creative" role → brainstorming, writing-skills skills appear
```

This prevents overwhelming new users while rewarding exploration.

## External Skills

The system supports skills from external sources:

```nix
source = {
  type = "external";
  url = "github:owner/repo";
  path = "skills/skill-name";
};
```

This allows:
- Community skill sharing
- Organization-specific skills
- Upstream skill tracking

## Dependencies

Skills can declare dependencies:

```nix
"my-skill" = {
  deps = ["brainstorming" "debugging"];
};
```

Dependencies are installed even if the user's roles wouldn't normally include them.

## Trade-offs

### Complexity vs. Flexibility

The role-based system is more complex than "install everything," but provides better organization and discoverability.

### Immutability vs. Customization

Symlinked skills can't be edited in place. Users must:
1. Create a custom skill in internal/
2. Override the manifest entry

This prevents drift but requires more intentional customization.

### Nix Dependency

Skills require a Nix rebuild to update. This trades immediate updates for reproducibility and atomicity.

## Future Directions

- **Skill dependencies**: Automatic transitive installation
- **Skill versions**: Track and update individual skills
- **Runtime discovery**: Query available skills without rebuild
- **Skill testing**: Validate skill content before installation
