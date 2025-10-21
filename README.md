# Nix System Configuration

A comprehensive, modular Nix Flakes configuration for managing macOS and NixOS systems with home-manager.

## 🚀 Features

- **Multi-platform support**: macOS (nix-darwin) and Linux (NixOS)
- **Modular architecture**: Shared configurations with role-based bundles
- **Comprehensive CI/CD**: Matrix builds, caching, and artifact publishing
- **Enhanced development environment**: Devenv with pre-commit hooks, formatters, and linters
- **Task automation**: Go-task integration for local and CI workflows
- **Code quality**: Automated formatting and linting with alejandra and deadnix

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

### Development Environment

The project uses [devenv](https://devenv.sh) for a consistent development environment with pre-commit hooks and development tools.

#### Pre-commit Hooks
- **Alejandra**: Nix code formatter (runs automatically on commit)
- **Deadnix**: Dead code detection (runs automatically on commit)

#### Available Tasks
```bash
task test              # Validate all configurations
task build             # Build all systems
task build:darwin      # Build macOS configurations
task build:nixos       # Build Linux configurations
task fmt               # Format Nix files with alejandra
task lint              # Run linters (deadnix)
task quality           # Run all code quality checks (fmt + lint)
task dev               # Enter development shell with all tools
task devenv:update     # Update devenv lock file

# Secrets Management (requires 1Password CLI)
task 1password:setup   # Set up 1Password CLI authentication
task 1password:status  # Check 1Password CLI status
task secrets:init      # Initialize secrets template
task secrets-get       # Retrieve secrets from 1Password
task secrets-set       # Store secrets in 1Password
```

#### Development Tools
The development environment includes:
- **Code formatting**: alejandra, nixpkgs-fmt
- **Linting**: deadnix
- **Language server**: nil
- **Analysis tools**: nix-tree, nvd
- **Utilities**: ripgrep, fd, jq, mdbook

### Secrets Management

This configuration supports secure secret management using 1Password CLI. Secrets are stored encrypted in 1Password and retrieved at build time.

#### Setup
1. **Install 1Password CLI**: Ensure `op` command is available
2. **Authenticate**: Run `task 1password:setup` to sign in
3. **Initialize secrets**: Run `task secrets:init` to create a secrets template
4. **Configure secrets**: Edit `secrets.nix` with your sensitive data
5. **Store securely**: Run `task secrets-set` to store in 1Password
6. **Enable in config**: Set `myConfig.secrets.enable = true` in your target

#### Supported Secrets
- Git configuration (username, email, GitHub tokens)
- API keys (OpenAI, Anthropic, etc.)
- Database credentials
- Cloud service credentials (AWS, DigitalOcean)
- Personal information

#### Security Notes
- Secrets file is gitignored and never committed
- 1Password provides end-to-end encryption
- Secrets are only accessible during Nix builds
- No secrets are stored in the Nix store

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
