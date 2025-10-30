{pkgs, ...}: {
  # macOS-specific packages and configuration
  environment.systemPackages = with pkgs; [
    # macOS-specific utilities
    google-chrome
    hidden-bar
    goose-cli
    claude-code
    alacritty-theme

    # Development tools with macOS support
    colima # Docker alternative for macOS

    # Additional system packages
    home-manager
  ];

  # 1Password integration
  programs = {
    _1password.enable = true;
    _1password-gui.enable = true;
    _1password.package = pkgs.unstable._1password-cli;
    _1password-gui.package = pkgs.unstable._1password-gui;
  };

  # Homebrew configuration
  homebrew = {
    enable = true;
    onActivation.cleanup = "uninstall";

    casks =
      [
        # Common macOS applications
        "raycast" # The version in nixpkgs is out of date
        "zed"
        "zen"
        "ollama-app"

        # Entertainment and communication
        "deezer"
        "block-goose"
        "pocket-casts"
        "steam"
      ]
      ++ (lib.optionals (config.system.primaryUser == "monkey") [
        # Only install Discord on MegamanX system
        "discord"
      ])
      ++ [
        # Productivity and utilities
        "obs"
        "sensei"
      ];
  };
}
