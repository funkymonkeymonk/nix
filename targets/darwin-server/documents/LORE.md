# LORE.md - History and Context

## Project Genesis
This OpenClaw installation was set up on April 11, 2026.
It represents a move toward declarative, reproducible AI assistant configuration.

## System Philosophy
- Nix-first approach to all system management
- Documentation lives with configuration
- Secrets managed separately from code
- Version control for all configuration changes

## Key Decisions
1. **Platform**: macOS with Apple Silicon - native app support, Unix environment
2. **Package Manager**: Determinate Nix - reproducible, declarative, rollback-capable
3. **Configuration**: Home Manager - user-level declarative management
4. **Interface**: Telegram - accessible from anywhere, simple bot model

## Evolution Notes
- Initial setup: Basic gateway with essential plugins
- Future: Additional plugins as needs emerge
- Goal: Fully automated, self-documenting system

## References
- Repository: github:openclaw/nix-openclaw
- Documentation: ~/code/openclaw-local/documents/
- Configuration: ~/code/openclaw-local/flake.nix
