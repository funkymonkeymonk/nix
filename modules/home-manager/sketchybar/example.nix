# Example configuration for using sketchybar with aerospace
# Add this to your host configuration (e.g., targets/MegamanX/default.nix or flake.nix)
_: {
  # Enable sketchybar in your myConfig
  myConfig.sketchybar = {
    enable = true;

    # Bar appearance
    height = 40;
    padding = 4;
    groupPadding = 10;

    # Fonts (requires SF Pro, SF Mono to be installed)
    font = {
      text = "SF Pro";
      numbers = "SF Mono";
    };

    # Colors (customize to match your theme)
    colors = {
      black = "#181819";
      white = "#e2e2e3";
      red = "#fc5d7c";
      green = "#9ed072";
      blue = "#76cce0";
      yellow = "#e7c664";
      orange = "#f39660";
      magenta = "#b39df3";
      grey = "#7f8490";

      bar = {
        bg = "#2c2e34";
        border = "#2c2e34";
      };

      popup = {
        bg = "#2c2e34";
        border = "#7f8490";
      };

      bg1 = "#363944";
      bg2 = "#414550";
    };

    # Enable aerospace integration
    useAerospaceIntegration = true;

    # Extra configuration (optional Lua code)
    extraConfig = "";
  };

  # You also need to enable homebrew fonts for the best experience
  homebrew = {
    enable = true;
    casks = [
      "font-sf-pro"
      "font-sf-mono-for-powerline"
      "sf-symbols"
    ];
  };
}
