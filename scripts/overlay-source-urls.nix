# Return external source URLs declared by derivations in the project overlay.
# Called by check-overlay-upstream-urls.sh for each representative host config.
{pkgs}: let
  overlay = (import ../overlays/default.nix {}) pkgs pkgs;
  # devenv and optional Bifrost packages are provided by flake inputs; their
  # source availability is governed by flake.lock rather than package src URLs.
  candidates = builtins.removeAttrs overlay ["devenv"];
  hasExternalSource = _: package:
    builtins.isAttrs package
    && (package.type or null) == "derivation"
    && package ? src
    && builtins.isAttrs package.src
    && package.src ? drvAttrs;
  packages = pkgs.lib.filterAttrs hasExternalSource candidates;
  sourceRecords = name: let
    package = packages.${name};
    sourceAttrs = package.src.drvAttrs;
    urls =
      sourceAttrs.urls
      or (
        if sourceAttrs ? url
        then [sourceAttrs.url]
        else []
      );
  in
    if urls == []
    then []
    else [
      {
        package = name;
        version = package.version or "unknown";
        inherit urls;
      }
    ];
in
  builtins.concatMap sourceRecords (builtins.attrNames packages)
