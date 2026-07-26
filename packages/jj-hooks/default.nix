# jj-hooks - Run pre-commit/prek/lefthook/hk hooks against jj bookmark pushes
# https://github.com/mattwilkinsonn/zireael/tree/main/tools/jj-hooks
#
# Ships two identical binaries: jj-hooks (canonical) and jj-hp (shorter alias).
# `jj-hp push` is a drop-in replacement for `jj git push` that runs the
# configured hook runner in an ephemeral git worktree before pushing.
#
# Packaged from prebuilt release tarballs (Rust project originally lived at
# mattwilkinsonn/jj-hooks, now developed in the mattwilkinsonn/zireael
# monorepo). Update the version + hashes together when bumping.
{
  lib,
  stdenvNoCC,
  fetchurl,
}: let
  version = "0.3.7";

  sources = {
    x86_64-linux = {
      platform = "linux-x64";
      hash = "sha256-UxGgtvfYmmIzyxwSWgAdqcKdSSwg5ld+lC1qvRxoJpQ=";
    };
    aarch64-linux = {
      platform = "linux-arm64";
      hash = "sha256-LOSBpcLgDik9x5QrVkjI+bl5DSOIwOHukuYET98OihY=";
    };
    aarch64-darwin = {
      platform = "darwin-arm64";
      hash = "sha256-Wq8QMc76Ubt5UeR1nujAnXePs/+g3NWR20t6Awlj5oU=";
    };
  };

  system = stdenvNoCC.hostPlatform.system;
  source =
    sources.${system}
    or (throw "jj-hooks: no prebuilt release for system '${system}'");
in
  stdenvNoCC.mkDerivation rec {
    pname = "jj-hooks";
    inherit version;

    src = fetchurl {
      url = "https://github.com/mattwilkinsonn/zireael/releases/download/v${version}/jj-hooks-v${version}-${source.platform}.tar.gz";
      hash = source.hash;
    };

    sourceRoot = "jj-hooks-v${version}-${source.platform}";

    dontBuild = true;

    installPhase = ''
      runHook preInstall

      install -Dm755 jj-hooks $out/bin/jj-hooks
      install -Dm755 jj-hp $out/bin/jj-hp

      runHook postInstall
    '';

    meta = with lib; {
      description = "Run pre-commit/prek/lefthook/hk hooks against jj bookmark pushes";
      homepage = "https://github.com/mattwilkinsonn/zireael/tree/main/tools/jj-hooks";
      license = licenses.asl20;
      maintainers = [];
      mainProgram = "jj-hp";
      platforms = builtins.attrNames sources;
    };
  }
