# TOOLS.md - Available Tools and Commands

## System Tools
- `nix` - Nix package manager
- `systemctl` - systemd service control
- `journalctl` - System logs
- `deploy-rs` - Deployment tool (if installed in VM)

## File Operations
- `ls`, `cat`, `find`, `grep`, `rg` (ripgrep)
- `cp`, `mv`, `rm`, `mkdir`
- `jq` - JSON processing
- `curl` - HTTP requests

## Network Tools
- `curl`, `wget` - HTTP clients
- `ping`, `netstat` - Network diagnostics
- `ssh` - Remote access to other systems
- `host` - DNS resolution

## Ollama Tools
- `curl http://host:11434/api/tags` - List models
- `curl http://host:11434/api/generate` - Generate text
- `curl http://host:11434/api/chat` - Chat completion

## NixOS-Specific Tools
- `nixos-rebuild` - System rebuild (if running locally)
- `nix-collect-garbage` - Garbage collection
- `nix-shell`, `nix run` - Temporary environments

## Development Tools
- `git` - Version control
- `vim`, `nano` - Text editors
- Standard Unix utilities

## How to Use Tools
- Always check if a tool is available before using it
- Use `which <tool>` to verify existence
- Prefer Nix-managed tools over manual installations
- Use explicit paths for scripts and binaries
- Document any custom tool installations

## Host Access
The VM can access the host (protoman) via:
- `http://host:11434` - Ollama API
- `192.168.1.192` - Host IP (if needed)

## Limitations
- Cannot directly control macOS on host (must SSH)
- No Homebrew (this is NixOS)
- Limited persistent storage (use virtiofs shares if needed)
