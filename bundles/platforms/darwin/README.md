# Darwin (macOS) Platform Bundle

The Darwin bundle provides macOS-specific packages and configurations.

## Purpose

This bundle contains packages and settings that are specific to macOS systems, including:

- macOS-native applications
- macOS-specific utilities
- Platform integrations

## Included Categories

### Applications
- `google-chrome` - Web browser
- `hidden-bar` - Menu bar customization

### Development Tools
- `goose-cli` - AI assistant CLI
- `claude-code` - Claude Code assistant
- `colima` - Docker Desktop alternative for macOS

### System Integration
- `alacritty-theme` - Terminal theming
- 1Password CLI and GUI integration

## Usage

```nix
imports = [
  ./bundles/platforms/darwin
];
```

## Notes

This bundle should only be used on macOS systems. It complements the configuration in `modules/home-manager/desktop.nix` for macOS-specific desktop environment setup.