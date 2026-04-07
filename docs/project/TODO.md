---
title: "Project TODO and Changelog"
description: "Completed work and remaining tasks for the Nix configuration repository"
type: reference
audience: both
last-reviewed: 2026-04-06
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
