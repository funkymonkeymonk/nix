---
name: writing-skills
description: Use when creating new skills, editing existing skills, or verifying skills work before deployment in this repository
---

# Writing Skills

## Overview

Skills in this repo are managed declaratively via `modules/home-manager/skills/manifest.nix` and deployed to both OpenCode and Pi agents. They follow conventions established in this repository (see `docs/reference/skill-development.md` for full guidelines).

**Core principle:** Every skill must have `name` + `description` YAML frontmatter, a `SKILL.md` under 500 lines, and appropriate roles in the manifest.

## Repository Conventions

### SKILL.md Requirements

**YAML frontmatter (required):**

```yaml
---
name: skill-name          # Must match directory name. lowercase, hyphens only
description: Use when...  # Triggering conditions ONLY. Never summarize workflow.
---
```

- `name`: Must match the directory name exactly. Max 64 chars. `a-z`, `0-9`, hyphens only.
- `description`: Start with "Use when...". Describe triggering conditions, symptoms, contexts. **Never summarize the skill's workflow or process** — agents may follow the description instead of reading the full skill.
- Keep under 500 lines. Move heavy reference material to `references/`.

### Manifest Registration

Every skill must be registered in `modules/home-manager/skills/manifest.nix`:

```nix
"skill-name" = {
  description = "Same as SKILL.md description";
  roles = ["opencode" "claude" "pi"];  # Add pi for general-purpose skills
  source = {
    type = "internal";
    path = ./internal/skill-name;
  };
  deps = [];
};
```

**Role guidelines:**
- `"opencode"`, `"claude"`, `"pi"` — agent roles; a skill needs at least one of these to ever load, and skills load identically for every agent enabled on a given host (agent-specific gating happens elsewhere, not via these tags)
- `"pi"` — add unless the skill is genuinely tied to opencode/claude-specific tooling (Task tool syntax, slash commands, etc.); most technique/reference skills are agent-agnostic and should include it
- `"workstation"`, `"creative"` — machine-class tags for skills tied to a specific role bundle beyond "has an AI assistant" (e.g. `innersource-pr-haiku` for work contexts, `brainstorming` for creative work)
- Do **not** add `"developer"` — every host with an AI-assistant role enabled also has `developer` enabled in practice, making it redundant; omitting it keeps the actual gating role explicit
- Keep roles minimal; agents load all matching skills

### Progressive Disclosure

1. **Metadata** (~100 tokens): `name` + `description` loaded at startup
2. **Instructions** (< 5000 tokens): Full `SKILL.md` loaded when activated
3. **Resources** (as needed): `references/`, `scripts/` loaded on demand

Keep `SKILL.md` focused. One excellent example beats five mediocre ones.

### Documentation Principles

**Do not document directory structures in `SKILL.md`.** Agents reviewing code can use `ls`, `find`, or file exploration tools to traverse the codebase. Tree diagrams in documentation rot quickly and add noise. Document *concepts* and *relationships*, not folder listings.

### Testing Skills

Follow TDD adapted for documentation:

1. **RED**: Run a scenario WITHOUT the skill. Document baseline failures.
2. **GREEN**: Write minimal skill addressing those failures.
3. **REFACTOR**: Close loopholes. Re-test.

For discipline-enforcing skills, test with pressure scenarios. For technique skills, test with application scenarios.

## Anti-Patterns

| Anti-Pattern | Fix |
|---|---|
| Summarizing workflow in `description` | Change to triggering conditions only |
| `SKILL.md` over 500 lines | Move heavy reference to `references/` |
| Documenting directory trees | Remove — agents use `ls`/`find` |
| Multi-language examples | One excellent example is enough |
| Narrative storytelling | Focus on reusable techniques |
| Missing `"pi"` role | Add for general-purpose skills |

## Deployment Checklist

- [ ] `name` matches directory name
- [ ] `description` starts with "Use when..." and doesn't summarize workflow
- [ ] `SKILL.md` under 500 lines
- [ ] Registered in `manifest.nix` with correct roles
- [ ] `devenv tasks run check:lint` passes
- [ ] Tested with baseline scenario (RED → GREEN → REFACTOR)
