# Skills Reference

Agent skills are defined in `modules/home-manager/skills/manifest.nix` and installed to `~/.config/opencode/skills/`.

## Available Skills

| Skill | Description | Roles |
|-------|-------------|-------|
| `brainstorming` | Use when creating or developing, before writing code or implementation plans - refines rough ideas into fully-formed designs through collaborative questioning, alternative exploration, and incremental validation. Don't use during clear 'mechanical' processes | creative, opencode, claude, pi |
| `condition-based-waiting` | Use when tests have race conditions, timing dependencies, or inconsistent pass/fail behavior - replaces arbitrary timeouts with condition polling to wait for actual state changes, eliminating flaky tests from timing guesses | opencode, claude, pi |
| `creating-user-manual` | Use when creating a personal user manual, manager README, or working-with-me document. Use when someone wants to document their working style, communication preferences, or collaboration patterns for colleagues | opencode, claude, pi |
| `defense-in-depth` | Use when invalid data causes failures deep in execution, requiring validation at multiple system layers - validates at every layer data passes through to make bugs structurally impossible | opencode, claude, pi |
| `devenv` | Use when working with devenv developer environments. Covers setup, packages, scripts, tasks, processes, services, git-hooks, and file generation. Use when initializing devenv, adding packages, configuring services like postgres/redis, running processes, or troubleshooting devenv issues | opencode, claude, pi |
| `diataxis-docs` | Use when updating, rewriting, or auditing documentation to follow the Diataxis framework | creative, opencode, claude, pi |
| `dispatching-parallel-agents` | Use when facing 3+ independent failures that can be investigated without shared state or dependencies - dispatches multiple agents to investigate and fix independent problems concurrently | opencode, claude, pi |
| `executing-plans` | Use when partner provides a complete implementation plan to execute in controlled batches with review checkpoints - loads plan, reviews critically, executes tasks in batches, reports for review between batches | opencode, claude, pi |
| `innersource-pr-haiku` | Use when given a GitHub PR link and asked to thank a contributor with a haiku and approve the PR | opencode, claude, pi, work |
| `iterating-nix-embedded-scripts` | Use when iterating on shell scripts embedded in Nix modules via writeShellScriptBin, writeShellApplication, writeScriptBin, or writeText — avoids slow build/switch cycles for every edit | opencode, claude, pi |
| `jj` | Use Jujutsu (jj) for version control. Treats pushed commits as immutable; every PR update adds a single new commit on top of the remote tip (no force pushes). Covers workflow, commits, bookmarks with Conventional Branch naming, pushing to GitHub, merge-based sync, stacked PRs, and workspaces for multi-project isolation | opencode, claude, pi |
