# Custom package overlays
final: _prev: {
  rtk = final.callPackage ../packages/rtk {};
  yaks = final.callPackage ../packages/yaks {};
  lume = final.callPackage ../packages/lume {};
  vane = final.callPackage ../packages/vane {};

  # Package Override Registry
  # See ../docs/reference/package-overrides.md for full documentation
  #
  # opencode 1.2.15 - Avoids edit/write hanging bug (Issue #20477)
  # Bug report: https://github.com/anomalyco/opencode/issues/20477
  # Status: Still open as of 2026-05-10 (affects v1.14.35 in nixpkgs)
  # Test to unlock: Run `opencode edit <large-file>` on macOS, verify no "Preparing write..." hang
  # Note: Uses fetchgit instead of fetchFromGitHub for hash stability
  opencode = _prev.opencode.overrideAttrs (oldAttrs: rec {
    version = "1.2.15";
    src = _prev.fetchgit {
      url = "https://github.com/anomalyco/opencode.git";
      rev = "refs/tags/v${version}";
      hash = "sha256-26MV9TbyAF0KFqZtIHPYu6wqJwf0pNPdW/D3gDQEUlQ=";
    };
    node_modules = oldAttrs.node_modules.overrideAttrs {
      outputHash = "sha256-71id1sB2dQ8Egj8zGFjcEIeOmU/t9HRoRwPHb9fWtC8=";
    };
  });

  openldap = _prev.openldap.overrideAttrs (_: {
    doCheck = false;
  });

  # super-productivity disabled: Electron 41 kqueue assertion crash on macOS.
  # Existing installed version (18.5.0) continues working.
  # super-productivity = _prev.super-productivity.overrideAttrs (oldAttrs: { ... });
}
