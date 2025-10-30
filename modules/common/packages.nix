{
  config,
  lib,
  pkgs,
  ...
}:
with lib; {
  imports = [./options.nix];

  config = {
    environment.systemPackages = with pkgs;
      [
        # Core utilities
        ripgrep
        fd
        coreutils

        # System monitoring
        htop

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
