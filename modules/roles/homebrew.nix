# Homebrew role for Darwin (macOS) systems
# Enables nix-homebrew integration and auto-migration
# Only import this for systems that have Homebrew installed
{
  config,
  lib,
  options,
  ...
}:
with lib; let
  cfg = config.myConfig.roles.homebrew;
  # Check if nix-homebrew module is available (imported by the flake)
  hasNixHomebrew = options ? nix-homebrew;
  # Also check if homebrew option exists
  hasHomebrew = options ? homebrew;
in {
  config = lib.mkIf cfg.enable (lib.mkMerge [
    # nix-homebrew settings (only if module is available)
    (lib.optionalAttrs hasNixHomebrew {
      nix-homebrew = {
        enable = true;
        user = (builtins.head config.myConfig.users).name;
        # autoMigrate disabled: we manage homebrew-core as a real git clone
        # so `brew update` works. nix-homebrew handles casks/brews installation
        # without taking over the tap infrastructure.
        autoMigrate = false;
      };
    })
    # homebrew casks (only if homebrew option exists)
    (lib.optionalAttrs hasHomebrew {
      homebrew = {
        enable = true;
        onActivation = {
          autoUpdate = false;
          cleanup = "none";
        };
        taps = [];
        brews = [];
        casks = [
          "raycast"
          "zed"
          "zen"
          "ghostty"
          "deezer"
          "sensei"
          "vivaldi"
          "1password"
        ];
      };
    })
  ]);
}
