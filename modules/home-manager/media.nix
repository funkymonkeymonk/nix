{
  config,
  lib,
  pkgs,
  ...
}: {
  # Media-related home configuration
  home.packages = with pkgs; [
    # YouTube download tools for TubeArchivist interaction
    yt-dlp
    # TubeArchivist CLI tools (if available)
    # tubearchivist-cli

    # Media management tools
    ffmpeg
    # Additional media utilities
  ];

  # Environment variables for TubeArchivist integration
  home.sessionVariables = {
    TA_URL = "http://localhost:8000";
    # YouTube API key should be set via secrets management
  };
}
