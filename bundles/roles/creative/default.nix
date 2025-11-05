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

    # Text processing and viewing
    pandoc
  ];
}
