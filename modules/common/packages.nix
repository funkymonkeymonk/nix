{
  config,
  lib,
  pkgs,
  ...
}:
with lib; {
  imports = [./options.nix];

  config = {
    # Enable zsh system-wide
    programs.zsh.enable = true;

    environment.systemPackages = with pkgs;
      [
        # Core utilities
        bat
        jq
        tree
        ripgrep
        fd
        coreutils

        # Development tools
        devenv
        direnv
        go-task

        # Shell and terminal
        fzf
        zinit

        # System monitoring
        htop
        watchman
        jnv

        # Text processing
        glow
        antigen
      ]
      ++ optionals config.myConfig.development.enable [
        # Additional development packages
        clang
        python3
        nodejs
        yarn
      ]
      ++ optionals config.myConfig.media.enable [
        # Media packages
        ffmpeg
        imagemagick
      ];
  };
}
