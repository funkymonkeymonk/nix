---
title: "Write Your First Agent Skill"
description: "Create a skill and deploy it through the personal Nix flake"
type: tutorial
audience: agent
last-reviewed: 2026-11-11
---

# Write Your First Agent Skill

In this tutorial, create a skill in the personal skills repository. Then deploy
it through the Nix flake.

## Prerequisites

- Access to the public `funkymonkeymonk/skills` repository.
- A checkout of that repository.
- A checkout of the personal Nix repository.

## 1. Create a skill directory

In the skills repository, create a directory for the skill:

```bash
mkdir -p skills/code-review-checklist
```

## 2. Write `SKILL.md`

Create `skills/code-review-checklist/SKILL.md` with this content:

```markdown
---
name: code-review-checklist
description: Use when reviewing code changes before approval or merge
---

# Code Review Checklist

Check correctness, edge cases, error paths, tests, and public interfaces.
```

The `name` must match the directory name. The `description` must tell an agent
when to use the skill.

## 3. Validate and publish the skill

Run the validation checks documented in the skills repository. Then push the
new skill to its `main` branch.

## 4. Pin the new revision

In the Nix repository, update the input lock:

```bash
nix flake update personal-skills
```

## 5. Check the Nix configuration

Run the configured lint and evaluation tests:

```bash
devenv tasks run check:lint
devenv tasks run test:eval
```

## 6. Deploy and verify

Switch the target machine. Then list the installed skill names:

```bash
find ~/.agents/skills -name SKILL.md -print
```

The new directory is available under `~/.agents/skills/code-review-checklist/`.
The agent can read `SKILL.md` and its supporting files there.

For the goal-oriented update steps, see [Update or add a skill](../how-to/add-skill.md).
