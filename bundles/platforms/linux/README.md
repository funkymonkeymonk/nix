# Linux Platform Bundle

The Linux bundle provides Linux-specific packages and configurations.

## Purpose

This bundle contains packages and settings that are specific to Linux systems, including:

- Linux-native applications
- Distribution-specific utilities
- Platform integrations

## Included Categories

### Applications
- Linux-specific applications

### System Tools
- Distribution-specific utilities

## Usage

```nix
imports = [
  ./bundles/platforms/linux
];
```

## Notes

This bundle should only be used on Linux systems. Currently minimal but ready for Linux-specific packages and configurations.