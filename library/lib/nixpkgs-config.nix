# Shared nixpkgs.config + base overlays for every Darwin/NixOS system
# built by this flake, whether through library/lib/mk-system.nix's
# mkDarwinSystem/mkNixosSystem helpers or a raw nix-darwin.lib.darwinSystem /
# nixpkgs.lib.nixosSystem call in flake.nix.
#
# Previously this same block (allowUnfree, permittedInsecurePackages,
# allowInsecurePredicate, and the stable/devenv/zellij-pane-tracker overlay
# list) was duplicated three times: once in flake.nix's `configuration`
# let-binding, and once each in mkDarwinSystem and mkNixosSystem. All three
# copies had drifted slightly (flake.nix's copy had two extra overlays
# and an allowUnfreePredicate not present in the other two).
#
# Usage: `(mkNixpkgsConfigModule {inherit inputs;})` as a module in a
# darwinSystem/nixosSystem modules list. Extra overlays specific to one
# call site (e.g. flake.nix's himalaya-tui) can be appended by the caller
# via a normal `nixpkgs.overlays = [...]` module alongside this one --
# NixOS module merging concatenates overlay lists automatically.
{inputs}: _: {
  nixpkgs = {
    config = {
      allowUnfree = true;
      permittedInsecurePackages = [
        "electron-39.8.10"
        "google-chrome-144.0.7559.97"
        "olm-3.2.16"
      ];
      allowInsecurePredicate = attrs: let
        pname = attrs.pname or attrs.name or "";
        fullName = "${pname}-${attrs.version or ""}";
      in
        pname
        == "openclaw"
        || builtins.elem fullName ["electron-39.8.10" "google-chrome-144.0.7559.97" "olm-3.2.16"];
    };
    overlays = [
      (final: _prev: {
        stable = import inputs.nixpkgs-stable {
          inherit (final) system config;
        };
      })
      # Use devenv 2.x from the cachix/devenv flake
      (final: _prev: {
        inherit (inputs.devenv.packages.${final.stdenv.hostPlatform.system}) devenv;
      })
      # zellij-pane-tracker WASM plugin from its own flake
      (final: _prev: {
        zellij-pane-tracker = inputs.zellij-pane-tracker.packages.${final.stdenv.hostPlatform.system}.default;
      })
      (import ../../overlays {inherit inputs;})
    ];
  };
}
