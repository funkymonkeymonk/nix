{
  config,
  pkgs,
  ...
}: {
  # System-level shell configuration
  # This module handles global shell setup that applies to all users

  # Enable zsh system-wide
  programs.zsh.enable = true;

  # Provide a system-wide /etc/zshrc managed by Nix
  # This sets SHELL to the Nix-provided zsh, initializes completion safely,
  # and sources the user's ~/.zshrc if present
  environment.etc."zshrc".text = ''
    # /etc/zshrc - system-wide configuration managed by Nix
    export SHELL=${pkgs.zsh}/bin/zsh

    ${
      if config.myConfig.ollama.enable
      then ''
        # Ollama configuration (set because myConfig.ollama is enabled)
        export OLLAMA_HOST="http://${config.myConfig.ollama.host}:${toString config.myConfig.ollama.port}"
      ''
      else ""
    }

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
