# TOOLS.md - Available Tools and Commands

## System Tools
- `nix` - Nix package manager
- `home-manager` - User environment management
- `darwin-rebuild` - macOS system configuration (if nix-darwin)
- `launchctl` - macOS service management
- `systemctl` - Service control (Linux only)

## File Operations
- `ls`, `cat`, `find`, `grep`, `rg` (ripgrep)
- `cp`, `mv`, `rm`, `mkdir`
- `jq` - JSON processing
- `curl` - HTTP requests

## Development Tools
- `git` - Version control
- `nodejs`, `pnpm` - JavaScript/TypeScript
- `python3` - Python scripting
- `ffmpeg` - Media processing

## macOS-Specific Tools
- `osascript` - AppleScript/JS for automation
- `screencapture` - Screenshots
- `open` - Open files/URLs/apps
- `pbpaste`, `pbcopy` - Clipboard access

## Media and AI Tools
- `whisper` - Audio transcription (OpenAI)
- `spotify-player` - Spotify control
- `peekaboo` - Screenshots (if enabled)
- `camsnap` - Camera snapshots (if enabled)

## Network Tools
- `curl`, `wget` - HTTP clients
- `ssh` - Remote access
- `ping`, `netstat` - Network diagnostics

## How to Use Tools
- Always check if a tool is available before using it
- Prefer Nix-managed tools over system defaults
- Use explicit paths for scripts and binaries
- Document any custom tool installations
