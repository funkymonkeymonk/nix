{lib, ...}: {
  # Disable nix-darwin documentation generation to speed up eval.
  # The docs require re-evaluating the entire config with scrubbed
  # derivations, which adds significant overhead on every rebuild.
  documentation.enable = false;

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
