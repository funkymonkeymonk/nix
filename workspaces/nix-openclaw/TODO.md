# TODO

## Completed ✓

### Foundation Restructure
- [x] Core created as minimal universal base (git, curl, vim, wget, coreutils, zsh)
- [x] Foundation builds on core (helix, zellij, fzf, docker, devenv, etc.)
- [x] Colima moved to foundation (works on Linux and macOS)
- [x] All duplicate packages cleaned up

### 1Password Integration
- [x] SSH agent enabled on all platforms
- [x] SSH_AUTH_SOCK configured
- [x] Sudo integration configured (basic)
- [x] Git signing with 1Password

### Configuration Migration
- [x] Syncthing moved to foundation
- [x] Jujutsu configuration moved to foundation
- [x] Docker moved to foundation
- [x] Ghostty configuration moved to foundation (Darwin-only)
- [x] Removed empty development.nix

### CI Tests Created
- [x] Core packages test (`devenv tasks run test:core`)
- [x] Foundation packages test (`devenv tasks run test:foundation`)
- [x] Options test (`devenv tasks run test:options`)
- [x] Configuration validation test (`devenv tasks run test:config`)
- [x] All tests task (`devenv tasks run test:all`)
- [x] Tests integrated into flake checks

## Remaining Tasks

### CI/CD Completed ✓
- [x] GitHub Actions workflow updated to run foundation tests
- [x] Test documentation created at `docs/reference/testing.md`
- [x] All CI jobs properly integrated with build report

### Testing (Need Real Systems)
- [ ] Test SSH key authentication with 1Password on actual system
- [ ] Test sudo authentication flow with 1Password
- [ ] Test fresh system bootstrap with new foundation
- [ ] Verify all changes work on both Darwin and NixOS hardware

### Future Improvements
- [ ] Research full PAM integration for biometric sudo on Linux
- [ ] Add more granular tests for individual modules
- [ ] Create NixOS VM integration tests for complex scenarios
