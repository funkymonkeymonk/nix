# Workstation Bundle

The workstation bundle provides general productivity and utility tools for daily computing.

## Purpose

This bundle supports general computing tasks including:

- Communication and collaboration
- System utilities
- Productivity tools

## Included Categories

### Communication
- `slack` - Team communication platform

### Networking
- `trippy` - Network diagnostic tool

### System Utilities
- `coreutils` - GNU core utilities
- `the-unarchiver` - Archive extraction tool
- `watchman` - File watching service
- `jnv` - JSON navigator

## Usage

```nix
imports = [
  ./bundles/roles/workstation
];
```

## Notes

This bundle provides general-purpose tools that complement specialized role bundles.