{inputs}: final: _prev: {
  # WHY: makes the project-locked devenv CLI available through the library module.
  # REMOVE WHEN: devenv is no longer used by the repo or nixpkgs matches the flake-pinned release.
  devenv = inputs.devenv.packages.${final.stdenv.hostPlatform.system}.devenv;
}
