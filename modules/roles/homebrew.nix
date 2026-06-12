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
        autoMigrate = mkDefault true;
      };
    })
    # homebrew casks (only if homebrew option exists)
    (lib.optionalAttrs hasHomebrew {
      homebrew = {
        enable = true;
        onActivation = {
          autoUpdate = false;
          cleanup = "uninstall";
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
