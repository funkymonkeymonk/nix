{pkgs, ...}: {
  # System-level shell configuration
  # This module handles global shell setup that applies to all users

  # Enable zsh system-wide
  programs.zsh.enable = true;

  # System-wide zsh init - works on both NixOS and Darwin
  programs.zsh.interactiveShellInit = ''
    export SHELL=${pkgs.zsh}/bin/zsh

  '';
}
