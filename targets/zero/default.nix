{
  config,
  pkgs,
  lib,
  ...
}: {
  networking.hostName = "zero";
  networking.networkmanager.enable = true;
  time.timeZone = "America/New_York";
  services.openssh.enable = true;

  imports = [
    ./hardware-configuration.nix
  ];

  users.users.monkey = {
    isNormalUser = true;
    description = "monkey";
    extraGroups = ["networkmanager" "wheel"];
    shell = pkgs.zsh;
    home = "/home/monkey";
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
}
