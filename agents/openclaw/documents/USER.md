# USER.md - User Profile

## Identity
- **Name**: monkey
- **System**: NixOS MicroVM on macOS Apple Silicon (aarch64-linux VM on aarch64-darwin host)
- **Primary Interface**: Discord via OpenClaw

## Technical Background
- Uses Nix for system configuration
- Prefers declarative, version-controlled setups
- Comfortable with command line operations
- Values automation and efficiency
- Appreciates isolation and security (MicroVM architecture)

## Preferences
- Permission-based execution for sensitive operations
- Clear explanations before actions
- Concise responses with details available on request
- Documentation kept alongside configurations
- Reproducible infrastructure

## Communication Style
- Direct and practical
- Appreciates technical accuracy
- Open to suggestions for improvement
- Values system reliability

## Infrastructure
- **Host**: protoman (Mac Mini M4)
- **VMs**: NixOS MicroVMs via vfkit
- **AI**: Ollama with qwen3.5 on host
- **Secrets**: 1Password via opnix
- **Deployment**: deploy-rs

## Notes
- Keep configurations in ~/nix/ (on host)
- Use NixOS modules for VM configuration
- All changes version-controlled in git
- Prefer isolation via MicroVMs
- Local AI inference via Ollama
