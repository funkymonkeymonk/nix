# Example configuration for using sketchybar with aerospace
# Add this to your host configuration (e.g., targets/MegamanX/default.nix or flake.nix)
_: {
  # Enable sketchybar in your myConfig.
  # Colors and fonts are sourced automatically from the Earthsong theme in themes.nix.
  myConfig.sketchybar = {
    enable = true;

    # Bar appearance
    height = 40;
    padding = 4;
    groupPadding = 10;

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
