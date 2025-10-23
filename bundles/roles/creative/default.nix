{
  _config,
  _lib,
  pkgs,
  ...
}: {
  # Creative role bundle - tools for media creation and editing
  environment.systemPackages = with pkgs; [
    # Media processing
    ffmpeg
    imagemagick

    # Note-taking and knowledge management
    logseq

    # Text processing and viewing
    glow
    pandoc
  ];
}
