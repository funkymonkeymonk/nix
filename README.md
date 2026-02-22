# Nix System Configuration

A comprehensive, modular Nix Flakes configuration for managing macOS and NixOS systems with home-manager. This repository provides a complete system management solution with cross-platform support, automated tooling, and enterprise-grade development workflows.

## Features

- **Multi-platform support**: macOS (nix-darwin) and Linux (NixOS) with unified configuration
- **Modular architecture**: Shared configurations with role-based bundles for different use cases
- **Window manager integration**: AeroSpace with floating dropdown terminal (Shift+Ctrl+Alt+G)
- **SSH commit signing**: 1Password-based git commit signing with biometric authentication
- **Comprehensive CI/CD**: Matrix builds, caching, and artifact publishing across platforms
- **Enhanced development environment**: Devenv with pre-commit hooks, formatters, linters, and task automation
- **Code quality**: Automated formatting and linting with alejandra and deadnix
- **Agent skills integration**: Automatic management of AI agent skills for OpenCode and Claude Code

## Project Structure

```
.
├── .github/                    # GitHub Actions workflows
├── modules/                    # Reusable Nix configurations
│   ├── common/                 # Shared configurations (options, users, shell, onepassword)
│   ├── home-manager/           # User environment modules
│   │   └── skills/             # Agent skills management
│   │       ├── install.nix     # Skills installation module
│   │       ├── manifest.nix    # Skill definitions and role assignments
│   │       ├── internal/       # Skills defined in this repo
│   │       └── external/       # Skills adapted from external sources
│   └── nixos/                  # Linux-specific modules
├── targets/                    # Machine-specific configurations
├── os/                         # Platform OS configurations
├── templates/                  # Templates for new configurations
├── bundles.nix                 # Consolidated package collections (roles + platforms)
├── flake.nix                   # Main Nix flake definition
├── devenv.nix                  # Development environment and task definitions
└── README.md                   # This file
```

## Development

### Prerequisites
- Nix with flakes enabled

### Quick Start
```bash
# Clone repository
git clone <repository-url>
cd nix

# Enter development environment
devenv shell

# Test configurations
devenv tasks run test

# Build all systems
devenv tasks run build

# Apply configuration
devenv tasks run switch

# Run code quality checks
devenv tasks run quality
```

### Shell Aliases

After configuration is applied, these aliases are available:
- `dt <task>` / `dtr <task>` - Run a devenv task
- `dtl` - List all tasks
- `t` - Run test:quick
- `tf` - Run test:full
- `s` - Run switch
- `q` - Run quality
- `b` - Run nix:build
- `i` - Run dev:ide

### Keyboard Shortcuts

- **Shift+Ctrl+Alt+G**: Toggle floating dropdown terminal (AeroSpace window manager)

### Development Environment

The project uses [devenv](https://devenv.sh) for a consistent development environment with pre-commit hooks and development tools.

#### Pre-commit Hooks
- **Alejandra**: Nix code formatter (runs automatically on commit)
- **Deadnix**: Dead code detection (runs automatically on commit)

### Cross-Platform Validation

The `devenv tasks run test:full` command provides comprehensive validation that works regardless of host platform:

- **On Darwin (macOS)**: Validates both Darwin and Linux configurations
- **On Linux**: Validates both Linux and Darwin configurations
- **Uses dry-run builds**: Tests build plans without actually building
- **Cross-architecture**: Validates x86_64-linux from aarch64-darwin and vice versa

**What it validates:**
- Flake structure and syntax (`nix flake check`)
- Linux configurations buildable (`nix build --dry-run`)
- macOS configurations evaluable (`nix eval`)
- All platform-specific packages and modules
- Home-manager configurations
- Cross-platform dependencies

#### Development Tools
The development environment includes:
- **Code formatting**: alejandra, nixpkgs-fmt, yamlfmt
- **Linting**: deadnix, statix, yamllint
- **Language server**: nil, nixd
- **Analysis tools**: nix-tree, nvd
- **Utilities**: ripgrep, fd, jq, mdbook

### Secrets Management

This configuration uses 1Password CLI directly for secret management. Secrets are accessed at runtime through 1Password's SSH agent and signing capabilities.

#### Setup
1. **Install 1Password CLI**: Ensure `op` command is available
2. **Enable 1Password SSH agent**: In 1Password app → Settings → Developer → Enable SSH agent
3. **Store SSH keys**: Add your SSH keys to 1Password for authentication and signing

#### How It Works
- **SSH Authentication**: Uses 1Password's SSH agent for key management
- **Git Signing**: Uses 1Password's `op-ssh-sign` program for commit signing on macOS
- **Runtime Access**: Secrets are accessed when needed, not stored in Nix configuration

#### Security Notes
- Secrets file is gitignored and never committed
- 1Password provides end-to-end encryption
- Secrets are only accessible during Nix builds
- No secrets are stored in the Nix store

## Agent Skills Management

This configuration includes automatic management of AI agent skills for OpenCode and Claude Code integration.

### Features
- **Automatic Installation**: Skills install automatically when `llm-client` or `llm-claude` roles are enabled
- **Role-Based Filtering**: Skills are assigned to roles and only installed when relevant roles are active
- **Local Customization**: Define custom skills in `modules/home-manager/skills/internal/`
- **Cross-Platform**: Works on all configured systems (macOS and NixOS)
- **Validation**: Skills follow Agent Skills specification compliance

### Usage

```bash
# Check skills status
devenv tasks run agent-skills:status

# Update skills from upstream
devenv tasks run agent-skills:update

# Validate skills format
devenv tasks run agent-skills:validate

# List available skills
skills-list
```

### Configuration

Agent skills are automatically enabled when `llm-client` or `llm-claude` roles are active (via the `enableAgentSkills` flag in bundles.nix). Skills are installed to:
- `~/.config/opencode/skills/` - Primary skills directory

### Adding Custom Skills

1. Create skill directory: `modules/home-manager/skills/internal/my-skill/`
2. Add `SKILL.md` with frontmatter (`name`, `description`)
3. Register in `modules/home-manager/skills/manifest.nix` with role assignments
4. Rebuild system to install

See [docs/agent-skills.md](docs/agent-skills.md) for detailed documentation.

### SSH Commit Signing

This configuration supports SSH-based git commit signing using 1Password, providing a modern alternative to GPG signing.

#### Features
- **Biometric authentication**: Uses Touch ID/Face ID for commit signing
- **Unified keys**: Same SSH key for authentication and signing
- **Secure storage**: Private keys never leave 1Password vault
- **Cross-platform**: Works on macOS, Linux, and Windows

#### Setup
1. **Enable 1Password SSH agent**: In 1Password app → Settings → Developer → Enable SSH agent
2. **Store SSH key in 1Password**: Add your SSH private key to 1Password
3. **Register public key**: Add your SSH public key to GitHub/GitLab/Bitbucket as a "Signing key" type
4. **Rebuild system**: Run `darwin-rebuild switch` to apply the configuration
5. **Test signing**: `git commit -m "test"` and verify with `git log --show-signature`

#### Configuration Details
The following Git configuration is applied automatically on macOS:
```bash
git config --global gpg.format ssh
git config --global commit.gpgsign true
git config --global gpg.ssh.program "/Applications/1Password.app/Contents/MacOS/op-ssh-sign"
```

1Password's `op-ssh-sign` program automatically determines which SSH key to use for signing based on your 1Password vault contents.

#### Verification
- GitHub/GitLab/Bitbucket will show commits as "Verified"
- Use `git log --show-signature` for local verification
- Biometric prompt appears for each signed commit

## CI/CD Pipeline

The repository includes automated testing and validation:

### Matrix Builds
- **x86_64-linux**: Ubuntu runners for NixOS configuration testing
- **aarch64-darwin**: macOS runners for Darwin configuration testing

### Features
- **Multi-architecture testing**: Validates flake configurations on both platforms
- **Automated formatting**: Ensures code style consistency with alejandra
- **Caching**: Nix store caching for faster CI runs

### Workflows
- **Pull requests**: Matrix testing and formatting validation
- **Main branch**: Matrix testing and formatting validation

### Weekly Flake Updates

- **Schedule**: Every Friday at 4:00 AM UTC
- **Function**: Updates flake.lock with latest package versions
- **Features**:
  - Automated basic fixes for common package renames
  - Comprehensive PR with technical details and summaries
  - Automatic cleanup of previous week's PR
  - Validation and reporting of all changes

The workflow creates PRs with the `flake-update` label and includes:
- Executive summary of changes
- Technical details of package updates
- List of automated fixes applied
- Validation results and next steps

## Architecture

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

## Customization

### Adding a New Machine
1. Create target configuration in `targets/`
2. Add flake output in `flake.nix`
3. Configure users and roles
4. Test with `devenv tasks run build`

### Adding a New Role
1. Add role definition in `bundles.nix` under `roles` attribute
2. Add documentation in `README.md`
3. Reference in flake configurations as needed

### Available Roles
All roles are defined in `bundles.nix`:
- `base` - Essential packages and shell aliases (always included)
- `developer` - Development tools (emacs, docker, k8s tools)
- `creative` - Media tools (ffmpeg, imagemagick, pandoc)
- `desktop` - Desktop applications (logseq, vivaldi on Linux)
- `workstation` - Work tools (slack, trippy)
- `entertainment` - Entertainment apps (steam, obs, discord via homebrew)
- `gaming` - Gaming tools (moonlight-qt)
- `agent-skills` - AI agent skills management
- `llm-client` - OpenCode with LLM server connection (auto-enables agent-skills)
- `llm-claude` - Claude Code integration (auto-enables agent-skills)
- `llm-host` - Ollama for local model hosting
- `llm-server` - LiteLLM server (placeholder)

### Adding a New Module
1. Create module in appropriate `modules/` subdirectory
2. Add options in `modules/common/options.nix`
3. Import in relevant flake configurations

## Status

### Completed
- Modular configuration system
- Multi-platform support (macOS + Linux)
- CI/CD pipeline with matrix testing
- Task automation via devenv
- Configuration validation
- Role-based bundles (developer, creative, gaming, workstation)
- Secret management with 1Password
- Window manager integration with AeroSpace (dropdown terminal, window rules)

### In Progress
- Performance optimizations

### Future
- GUI application management
- Backup automation
- Monitoring and alerting
