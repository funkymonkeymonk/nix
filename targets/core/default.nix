# Core bootstrap configuration
# Provides essential tools (devenv, direnv, git, etc.) for working with this repo
# This is a minimal configuration that doesn't require user-specific settings
{pkgs, ...}: {
  # Essential packages for repo development
  environment.systemPackages = with pkgs; [
    git
    devenv
    direnv
  ];

  # Enable zsh as default shell
  programs.zsh.enable = true;
}
