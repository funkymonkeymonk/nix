---
title: "Project TODO and Changelog"
description: "Completed work and remaining tasks for the Nix configuration repository"
type: reference
audience: both
last-reviewed: 2026-04-07
---

# Project Tasks

## Changelog (Completed Work)

### Foundation Restructure
**Date:** 2025-03
- [x] Core created as minimal universal base (git, curl, vim, wget, coreutils, zsh)
- [x] Foundation builds on core (helix, zellij, fzf, docker, devenv, etc.)
- [x] Colima moved to foundation (works on Linux and macOS)
- [x] All duplicate packages cleaned up

### 1Password Integration
**Date:** 2025-03
- [x] SSH agent enabled on all platforms
- [x] SSH_AUTH_SOCK configured
- [x] Sudo integration configured (basic)
- [x] Git signing with 1Password

### Configuration Migration
**Date:** 2025-03
- [x] Syncthing moved to foundation
- [x] Jujutsu configuration moved to foundation
- [x] Docker moved to foundation
- [x] Ghostty configuration moved to foundation (Darwin-only)
- [x] Removed empty development.nix

### CI Tests Created
**Date:** 2025-03
- [x] Core packages test (`devenv tasks run test:core`)
- [x] Foundation packages test (`devenv tasks run test:foundation`)
- [x] Options test (`devenv tasks run test:options`)
- [x] Configuration validation test (`devenv tasks run test:config`)
- [x] All tests task (`devenv tasks run test:all`)
- [x] Tests integrated into flake checks

### CI/CD Improvements
**Date:** 2025-03
- [x] GitHub Actions workflow updated to run foundation tests
- [x] Test documentation created at `docs/reference/testing.md`
- [x] All CI jobs properly integrated with build report

### Multi-Agent Repository Workflow Module
**Date:** 2025-04
- [x] Disko configuration for `/srv` volume
- [x] Local GitHub mirrors in `/srv/github/` per configured project
- [x] Automatic sync (5min during agent sessions, 1hr idle)
- [x] Per-agent jj workspaces in `~/workspaces/`
- [x] Stacked PR support with conventional branch naming
- [x] Auto-cleanup after merge
- [x] `fjj` command with fzf integration

### Documentation Improvements
**Date:** 2026-04-06
- [x] Documentation review completed
- [x] Created automated OpenClaw MicroVM setup guide
- [x] Enhanced AGENTS.md with MicroVM automation section
- [x] Updated docs/index.md with metadata and navigation
- [x] Cleaned up README.md (removed TODO section, trailing comment)
- [x] Archived TODO.md to docs/project/TODO.md

---

## Remaining Tasks

### Testing (Requires Real Systems)
**Priority:** High
**Blocked by:** Need physical hardware access
- [ ] Test SSH key authentication with 1Password on actual system
- [ ] Test sudo authentication flow with 1Password
- [ ] Test fresh system bootstrap with new foundation
- [ ] Verify all changes work on both Darwin and NixOS hardware

### Future Improvements
**Priority:** Medium
- [ ] Research full PAM integration for biometric sudo on Linux
- [ ] Add more granular tests for individual modules
- [ ] Create NixOS VM integration tests for complex scenarios
- [ ] Auto-generate options.md from Nix code
- [ ] Add architecture diagrams to explanation docs

### yx Sync - High Value (P1)
**Priority:** High
**Source:** yx sync 2026-04-07
- [ ] Add explicit permissions blocks to all CI workflows
- [ ] Add failure notifications for scheduled CI workflows
- [ ] Add home-manager module composition tests
- [ ] Add role-specific package tests
- [ ] Add skills manifest validation test
- [ ] Consolidate bundles.nix vs modules/roles/ duplication
- [ ] Extract facter.json stub to shared CI script
- [ ] Fix fjj.nix ignoring myConfig.fjj.mirrorRoot option
- [ ] Fix llm-host.nix ignoring myConfig.sharedModels
- [ ] Fix vane API keys stored in world-readable Nix store
- [ ] Integrate jj skill tests into CI
- [ ] Move inline config from flake.nix to targets/
- [ ] Re-enable Linux build in main-build.yml
- [ ] Replace hardcoded config fallback lists in pr-validation.yml

### yx Sync - Cleanup (P2)
**Priority:** Medium
**Source:** yx sync 2026-04-07
- [ ] Add stateVersion consistently to all microvm targets
- [ ] Consolidate programs.zsh.enable (set in 3 places)
- [ ] Extract shared LLM env vars from llm-client.nix and llm-claude.nix
- [ ] Fix entertainment role being no-op on NixOS
- [ ] Fix homebrew casks in creative/desktop roles failing on NixOS
- [ ] Fix vane autoStart option being ignored by darwin.nix
- [ ] Remove dead generate-env.sh in microvm targets
- [ ] Remove dead perform_installation() in installer.nix
- [ ] Remove duplicate claude-code from foundation.nix (belongs in llm-claude)
- [ ] Remove duplicate development.enable vs roles.developer.enable options
- [ ] Remove empty llm-server bundle in bundles.nix
- [ ] Remove unused _config param in os/darwin.nix
- [ ] Remove unused ollama.useHomebrew option
- [ ] Unify nix.settings.experimental-features across modules

### yx Sync - Nice to Have (P3)
**Priority:** Low
**Source:** yx sync 2026-04-07
- [ ] Abstract NVIDIA config from targets/zero into reusable module
- [ ] Add cross-platform option guard tests
- [ ] Add overlay tests for custom packages (rtk, yaks, pi-coding-agent)
- [ ] Add workflow_dispatch trigger to pr-validation.yml
- [ ] Consolidate two separate installer implementations
- [ ] Create Darwin target template (templates/new-target-darwin.nix)
- [ ] Extract jj-autosync.nix embedded bash to separate .sh files
- [ ] Implement mergiraf as AST-aware merge tool
- [ ] Move boot.loader settings in os/nixos.nix behind lib.mkDefault
- [ ] Remove hardcoded monitor name in aerospace.nix
- [ ] Replace types.attrs with typed attrsets in options.nix
- [ ] Split options.nix into per-feature option files
- [ ] Unify hardware abstraction across targets (facter vs pathExists vs stub)

---

## How to Update This File

When completing a task:
1. Move from "Remaining Tasks" to "Changelog"
2. Add completion date
3. Update `last-reviewed` in metadata

When adding a new task:
1. Add to appropriate section under "Remaining Tasks"
2. Set priority (High/Medium/Low)
3. Add any blocking dependencies

---

## Related Documents

- [AGENTS.md](../../AGENTS.md) - Agent-specific guidance
- [docs/how-to/run-ci-locally.md](../how-to/run-ci-locally.md) - Testing documentation
- [docs/reference/ci.md](../reference/ci.md) - CI/CD pipeline reference
