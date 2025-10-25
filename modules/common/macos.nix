{
  config,
  lib,
  ...
}: {
  options.myConfig.macos = {
    enable = lib.mkEnableOption "macOS-specific system configuration";
  };

  config = lib.mkIf config.myConfig.macos.enable {
    # Disable nix-daemon to avoid conflicts with system-installed nix
    nix.enable = false;

    # macOS system defaults
    system.defaults = {
      NSGlobalDomain.AppleInterfaceStyle = "Dark";
      dock = {
        autohide = true;
      };
    };
  };
}
