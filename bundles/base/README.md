# Base Bundle

The base bundle provides essential system packages that should be available on all systems.

## Purpose

This bundle contains the minimal set of packages required for basic system functionality. It serves as the foundation that other role-based bundles build upon.

## Included Packages

- Core system utilities
- Basic development tools
- Shell environments

## Usage

Import this bundle in your system configuration:

```nix
imports = [
  ./bundles/base
];
```

## Notes

Most packages are now handled by the modular system in `modules/common/packages.nix`. This bundle is kept for organizational purposes and potential future platform-specific base packages.