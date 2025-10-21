# Nix System Configuration

A comprehensive, modular Nix Flakes configuration for managing macOS and NixOS systems with home-manager.

## 🚀 Features

- **Multi-platform support**: macOS (nix-darwin) and Linux (NixOS)
- **Modular architecture**: Shared configurations with role-based bundles
- **Comprehensive CI/CD**: Matrix builds, caching, and artifact publishing
- **Development environment**: Devenv integration with pre-commit hooks
- **Task automation**: Go-task integration for local and CI workflows

## 📁 Project Structure

```
.
├── bundles/                    # Package collections by role/platform
│   ├── base/                   # Essential packages
│   ├── roles/                  # Role-based bundles (developer, creative, etc.)
│   └── platforms/              # Platform-specific packages
├── modules/                    # Reusable Nix configurations
│   ├── common/                 # Shared configurations
│   ├── home-manager/           # User environment modules
│   └── nixos/                  # Linux-specific modules
├── targets/                    # Machine-specific configurations
├── os/                         # Platform OS configurations
└── Taskfile.yml               # Task automation
```

## 🛠️ Development

### Prerequisites
- Nix with flakes enabled
- Go-task (installed via nix)

### Quick Start
```bash
# Clone repository
git clone <repository-url>
cd nix

# Test configurations
task test

# Build all systems
task build

# Format code
task fmt
```

### Available Tasks
```bash
task test              # Validate all configurations
task build             # Build all systems
task build:darwin      # Build macOS configurations
task build:nixos       # Build Linux configurations
task fmt               # Format Nix files
```

## 🤖 CI/CD Pipeline

The repository includes a comprehensive CI/CD pipeline with:

### Matrix Builds
- **x86_64-linux**: Ubuntu runners for NixOS testing
- **aarch64-darwin**: macOS runners for Darwin testing

### Features
- **Multi-architecture testing**: Validates configurations on both platforms
- **Nix caching**: Fast builds with DeterminateSystems/nix-cache-action
- **Artifact publishing**: Build artifacts for releases
- **macOS integration testing**: Aerospace, Homebrew, and macOS-specific features
- **Optional Cachix publishing**: For faster downstream builds

### Workflows
- **Pull requests**: Full matrix testing and formatting validation
- **Main branch**: Additional macOS integration tests and caching
- **Tagged releases**: Artifact publishing and release creation

## 🏗️ Architecture

### Modular System
- **Modules**: Reusable configuration logic (how things work)
- **Bundles**: Package collections (what gets installed)
- **Options**: Type-safe configuration with validation

### Supported Systems
- **macOS**: Will-Stride-MBP, MegamanX (aarch64-darwin)
- **NixOS**: drlight, zero (x86_64-linux)

### Configuration Flow
1. **Options** define available configuration
2. **Modules** implement configuration logic
3. **Bundles** provide package collections
4. **Flake** composes everything for each system

## 🔧 Customization

### Adding a New Machine
1. Create target configuration in `targets/`
2. Add flake output in `flake.nix`
3. Configure users and roles
4. Test with `task build:{platform}:{machine}`

### Adding a New Role
1. Create bundle in `bundles/roles/`
2. Add documentation in `README.md`
3. Update flake configurations as needed

### Adding a New Module
1. Create module in appropriate `modules/` subdirectory
2. Add options in `modules/common/options.nix`
3. Import in relevant flake configurations

## 📋 Status

### ✅ Completed
- Modular configuration system
- Multi-platform support (macOS + Linux)
- Comprehensive CI/CD pipeline
- Task automation
- Configuration validation
- Role-based bundles

### 🔄 In Progress
- Secret management with 1Password
- Additional role bundles (gaming, workstation)
- Performance optimizations

### 📝 Future
- GUI application management
- Backup automation
- Monitoring and alerting
