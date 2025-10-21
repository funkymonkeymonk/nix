# Developer Bundle

The developer bundle provides comprehensive tools for software development and system administration.

## Purpose

This bundle is designed for developers who need a full development environment including:

- Version control tools
- Programming languages and runtimes
- Container and orchestration tools
- Cloud utilities
- Development editors

## Included Categories

### Version Control
- `git` - Distributed version control
- `gh` - GitHub CLI

### Development Tools
- `devenv` - Development environment manager
- `direnv` - Environment variable manager
- `go-task` - Task runner

### Programming Languages
- `clang` - C/C++ compiler
- `python3` - Python runtime
- `nodejs`, `yarn` - JavaScript runtime and package manager

### Container & Orchestration
- `docker` - Container runtime
- `colima` - Docker Desktop alternative for macOS
- `k3d` - Lightweight Kubernetes
- `kubectl` - Kubernetes CLI
- `kubernetes-helm` - Kubernetes package manager
- `k9s` - Kubernetes TUI

### Utilities
- `bat` - Enhanced cat
- `jq` - JSON processor
- `ripgrep` - Fast text search
- `fd` - Modern find
- `htop` - Process viewer

## Usage

```nix
imports = [
  ./bundles/roles/developer
];
```

## Notes

This bundle provides tools that complement the configuration in `modules/home-manager/development.nix`.