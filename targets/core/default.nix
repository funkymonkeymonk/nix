# Core target configuration
#
# This is a minimal configuration that provides essential tools for working
# with this Nix flake repository. It includes:
# - devenv: Development environment manager
# - direnv: Automatic environment loading
# - Base role packages (git, vim, gh, bat, jq, etc.)
#
# This configuration is platform-agnostic and is used by the bootstrap.sh
# script to set up a new machine with the minimum required tools.
{
  config,
  lib,
  pkgs,
  ...
}: {
  # Core packages - these are essential for working with this repository
  # and provide a good baseline for any system
  environment.systemPackages = with pkgs; [
    # Essential development environment tools
    devenv
    direnv

    # Version control
    git
    gh

    # Essential CLI tools (subset of base role)
    vim
    bat
    jq
    tree
    fzf
    zsh
    ripgrep
    fd
    coreutils
    htop
    glow
  ];

  # Enable zsh as it's needed for the development workflow
  programs.zsh.enable = true;

  # Essential shell aliases for working with this repo
  environment.shellAliases = {
    # Git aliases
    g = "git";
    gst = "git status";
    gpush = "git push";
    gpull = "git pull";
    gd = "git diff";

    # Nix tools
    try = "nix-shell -p";

    # Navigation
    "..." = "cd ../..";
  };

  # Environment variables
  environment.variables = {
    EDITOR = "vim";
  };
}
