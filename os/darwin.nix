{lib, ...}: {
  nixpkgs.config.allowUnfree = true;
  nixpkgs.config.allowUnfreePredicate = pkg:
    builtins.elem (lib.getName pkg) [
      "claude-code"
    ];

  nix.enable = false;

  # Require password for each sudo command
  security.sudo.extraConfig = ''
    Defaults timestamp_timeout=0
  '';

  system.defaults = {
    NSGlobalDomain.AppleInterfaceStyle = "Dark";
    dock = {
      autohide = true;
    };
  };
}
