# DevContainer Usage

This repository includes a DevContainer configuration for running opencode in a Docker container with NixOS and devenv support.

## 🚀 Quick Start

### Using VS Code
1. Open this repository in VS Code
2. Install the "Dev Containers" extension
3. Press `Ctrl+Shift+P` (or `Cmd+Shift+P` on macOS)
4. Select "Dev Containers: Reopen in Container"
5. Wait for the container to build and start

### Using Docker CLI
```bash
# Build the container
docker build -t nix-devcontainer .devcontainer/

# Run the container
docker run -it --privileged --cap-add=SYS_PTRACE \
  -v $(pwd):/workspace \
  -p 3000:3000 -p 8000:8000 -p 9000:9000 \
  nix-devcontainer
```

## 📦 Features

- **NixOS Base**: Full NixOS environment with flakes enabled
- **Devenv Integration**: Project-specific dependencies loaded on container start
- **opencode User**: Pre-configured user with git and development tools
- **Docker Support**: Docker-in-Docker for container operations
- **VS Code Extensions**: Pre-installed Nix IDE and development extensions

## 🛠️ Development Environment

The DevContainer includes:

- **Shell**: Zsh with Nix integration
- **Package Manager**: Nix with flakes and devenv
- **Version Control**: Git with pre-configured user settings
- **Task Runner**: Go-task for project automation
- **Development Tools**: curl, wget, vim, and common utilities

## 📁 Container Structure

- **User**: `opencode` with sudo privileges
- **Home**: `/home/opencode`
- **Workspace**: `/workspace` (mounted from host)
- **Shell**: `/run/current-system/sw/bin/zsh`

## 🔧 Configuration

### Git Settings
```bash
git config --global user.name "opencode"
git config --global user.email "opencode@devcontainer.local"
git config --global init.defaultBranch "main"
```

### Devenv Integration
The container automatically initializes devenv on startup:
```bash
# devenv shell is sourced and ready
# Project dependencies are loaded
# Development tools are available
```

### VS Code Extensions
- `jnoortheen.nix-ide`: Nix language support
- `mkhl.direnv`: Direnv integration
- `ms-vscode-remote.remote-containers`: DevContainer support

## 🎯 Usage Examples

### Running opencode
```bash
# The opencode command is available in the container
task opencode
```

### Building Configurations
```bash
# Test the flake
task test

# Build all systems
task build

# Format code
task fmt
```

### Development Workflow
```bash
# Enter devenv shell (already sourced)
devenv shell

# Install additional packages
nix profile install nixpkgs#package-name

# Update dependencies
nix flake update
```

## 🔍 Troubleshooting

### Container Build Issues
- Ensure Docker is running and has sufficient resources
- Check that Docker has permission to access the repository directory
- Verify that all required files are present in `.devcontainer/`

### Permission Issues
- The container runs with `--privileged` flag for system access
- User `opencode` has sudo privileges for administrative tasks
- Docker socket is mounted for container operations

### Performance Tips
- Allocate sufficient RAM to Docker (recommended: 4GB+)
- Use SSD storage for better I/O performance
- Limit background processes in the container

## 🔄 Updates

To update the DevContainer:

1. **Rebuild the container**:
   ```bash
   docker build --no-cache -t nix-devcontainer .devcontainer/
   ```

2. **Update flake dependencies**:
   ```bash
   nix flake update
   ```

3. **Restart the container** in VS Code:
   - Press `Ctrl+Shift+P`
   - Select "Dev Containers: Rebuild Container"

## 📚 Additional Resources

- [Dev Containers Documentation](https://containers.dev/)
- [NixOS Manual](https://nixos.org/manual/nixos/stable/)
- [Devenv Documentation](https://devenv.sh/)
- [Nix Flakes Documentation](https://nixos.wiki/wiki/Flakes)