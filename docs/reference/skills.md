# Skills Reference

Skills come from the pinned public `personal-skills` flake input and install to `~/.agents/skills/`.

## Available Skills

| Skill | Description |
|-------|-------------|
| `brainstorming` | You MUST use this before any creative work - creating features, building components, adding functionality, modifying behavior, or planning anything new, in software or out of it (a talk, a business, a renovation). |
| `consumer-decision-guides` | Use when researching or writing consumer buying guides, product or service comparisons, best-of roundups, or Wirecutter-inspired recommendation articles - creates reader-first decision guides with transparent evidence, testing, tradeoffs, and clear picks. |
| `creating-user-manual` | Use when creating a personal user manual, manager README, or working-with-me document. Use when someone wants to document their working style, communication preferences, or collaboration patterns for colleagues. |
| `devenv` | Use when working with devenv developer environments. Covers setup, packages, scripts, tasks, processes, services, git-hooks, and file generation. Use when initializing devenv, adding packages, configuring services like postgres/redis, running processes, or troubleshooting devenv issues. |
| `diagnosing-superpowers` | Use when a superpowers session went wrong and your human partner wants to know why — repeated work, ignored plans, stumbles, poor results, a skill that didn't fire, "it took too long", "why is it so expensive", "what is it doing" — or wants to build a bug report for the superpowers maintainers, for the current session or a past one identified by id or path, on any harness. |
| `diataxis-docs` | Use when you need to select or review a Diataxis form for reader-facing technical documentation, such as tutorials, how-to guides, reference, or explanations. |
| `dispatching-parallel-agents` | Use when facing 2+ independent tasks that can be worked on without shared state or sequential dependencies |
| `executing-plans` | Use when executing an implementation plan in the current session as the implementer yourself — your human partner chose inline execution, or no subagent tool is available |
| `finishing-a-development-branch` | Use when implementation is complete, all tests pass, and you need to decide how to integrate the work |
| `receiving-code-review` | Use when receiving code review feedback, before implementing suggestions, especially if feedback seems unclear or technically questionable - requires technical rigor and verification, not performative agreement or blind implementation |
| `requesting-code-review` | Use when completing tasks, implementing major features, or before merging to verify work meets requirements |
| `reversible-decisions` | Use when an agent must decide whether to ask the user before a change, choose between options, or assess reversal cost. |
| `ste-technical-writing` | Use when creating, editing, or reviewing technical documentation, including ADRs, specifications, implementation plans, tutorials, how-to guides, and reference. |
| `subagent-driven-development` | Use when executing implementation plans with independent tasks in the current session |
| `systematic-debugging` | Use when encountering any bug, test failure, or unexpected behavior, before proposing fixes |
| `test-driven-development` | Use when implementing any feature or bugfix, before writing implementation code |
| `using-git-worktrees` | Use when starting feature work that needs isolation from current workspace or before executing implementation plans - ensures an isolated workspace exists via native tools or git worktree fallback |
| `using-superpowers` | Use when starting any conversation - establishes how to find and use skills, requiring skill invocation before ANY response including clarifying questions |
| `verification-before-completion` | Use when about to claim work is complete, fixed, or passing, before committing or creating PRs - requires running verification commands and confirming output before making any success claims; evidence before assertions always |
| `writing-plans` | Use when you have a spec or requirements for a multi-step task, before touching code |
| `writing-skills` | Use when creating new skills, editing existing skills, or verifying skills work before deployment |

## Installation

When `developer`, `creative`, `workstation`, `opencode`, `claude`, or `pi` is
enabled, Home Manager links complete skill directories to `~/.agents/skills/`.
The flake lock file pins the source revision. Update it with:

```bash
nix flake update personal-skills
```

Run `find ~/.agents/skills -name SKILL.md -print` to list installed skills.
Add or edit skills in the source repository, update this input, and rebuild.
