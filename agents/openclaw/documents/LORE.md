# LORE.md - History and Context

## Project Genesis
This OpenClaw installation was set up on April 29, 2026.
It represents a move toward declarative, reproducible AI assistant configuration
with enhanced isolation via NixOS MicroVMs.

## System Philosophy
- **Nix-first approach**: All system management via Nix flakes
- **Documentation lives with configuration**: Version-controlled docs
- **Secrets managed separately**: 1Password integration via opnix
- **Isolation**: MicroVM architecture for security
- **Version control**: All changes tracked in git

## Key Decisions
1. **Platform**: NixOS MicroVM on macOS Apple Silicon via vfkit
2. **AI**: Ollama (qwen3.5) running on host for local inference
3. **Configuration**: NixOS modules - system-level declarative management
4. **Interface**: Discord - accessible from anywhere
5. **Deployment**: deploy-rs for remote management
6. **Secrets**: 1Password with service account token

## Evolution Notes
- **Initial setup**: April 2026 - Migrated from macOS Home Manager to NixOS VM
- **Previous**: Ran directly on macOS via Home Manager
- **Current**: Isolated NixOS VM with host Ollama access
- **Future**: Additional MicroVMs for different services
- **Goal**: Fully automated, self-documenting, reproducible infrastructure

## Architecture
```
Discord DM → OpenClaw Gateway (NixOS VM) → Ollama (host: qwen3.5)
                ↓
         1Password (opnix)
                ↓
         /var/lib/openclaw/secrets/
```

## References
- Repository: github:funkymonkeymonk/nix
- Documents: agents/openclaw/documents/
- Configuration: targets/microvms/openclaw-vfkit.nix
- Deployment: flake.nix (deploy.nodes.openclaw-vm)
