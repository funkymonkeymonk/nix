{
  config,
  pkgs,
  lib,
  ...
}:
# NixOS module for the `drlight` machine.
# - Sets up the `monkey` user with zsh as the login shell
# - Installs zsh system-wide
# - Enables programs.zsh
# - Provides a system-wide /etc/zshrc that sources each user's ~/.zshrc
# - Configures basic networking / SSH settings used in flake.nix
{
  imports = [
    ./hardware-configuration.nix
  ];

  # Ensure the user exists with the desired shell and groups
  users.users.monkey = {
    isNormalUser = true;
    description = "monkey";
    extraGroups = ["networkmanager" "wheel"];
    # Use the zsh from nixpkgs as the login shell
    shell = pkgs.zsh;
    # Keep explicit home to match other entries; adjust if you prefer default
    home = "/home/monkey";
  };

  # Make sure zsh is available system-wide (so the shell path exists)
  environment.systemPackages = with pkgs; [
    zsh
  ];

  # Enable NixOS-provided zsh options; this will register zsh with
  # system configuration and provides common zsh helpers.
  programs.zsh = {
    enable = true;
    # Additional global zsh settings can be added here if desired.
  };

  # Provide a minimal system-wide /etc/zshrc managed by Nix.
  # It sets SHELL to the Nix-provided zsh, initializes completion safely,
  # and sources the user's ~/.zshrc if present.
  environment.etc."zshrc".text = ''
    # /etc/zshrc - system-wide configuration managed by Nix
    export SHELL=${pkgs.zsh}/bin/zsh

    # Load zshenv if present (follow distribution's behavior)
    if [ -f /etc/zsh/zshenv ]; then
      . /etc/zsh/zshenv
    fi

    # Initialize completion if available (safe/optional)
    if command -v compinit >/dev/null 2>&1; then
      autoload -Uz compinit && compinit || true
    fi

    # Source user's ~/.zshrc to allow per-user customizations
    if [ -n "$HOME" ] && [ -f "$HOME/.zshrc" ]; then
      . "$HOME/.zshrc"
    fi
  '';

  # Host/network/time/SSH settings for drlight
  networking.hostName = "drlight";
  networking.networkmanager.enable = true;
  time.timeZone = "America/New_York";

  services.openssh.enable = true;
}
