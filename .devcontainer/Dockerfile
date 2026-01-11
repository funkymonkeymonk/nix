# Use NixOS as base image
FROM nixos/nix:latest

# Set environment variables
ENV NIX_CONFIG="experimental-features = nix-command flakes"
ENV DEVENV_HOME="/home/opencode/.local/share/devenv"

# Create opencode user
RUN useradd -m -s /run/current-system/sw/bin/zsh opencode && \
    usermod -aG docker opencode

# Install required packages
RUN nix profile install nixpkgs#devenv nixpkgs#git nixpkgs#go-task nixpkgs#zsh

# Set working directory
WORKDIR /workspace

# Copy the flake and devenv configuration
COPY flake.nix devenv.nix ./
COPY bundles/ ./bundles/
COPY modules/ ./modules/
COPY targets/ ./targets/
COPY os/ ./os/
COPY Taskfile.yml ./

# Initialize devenv
RUN devenv shell --init

# Switch to opencode user
USER opencode

# Set up git configuration for opencode user
RUN git config --global user.name "opencode" && \
    git config --global user.email "opencode@devcontainer.local" && \
    git config --global init.defaultBranch "main"

# Expose common development ports
EXPOSE 3000 8000 9000

# Default command
CMD ["zsh"]