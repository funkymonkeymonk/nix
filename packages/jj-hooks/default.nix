# jj-hooks - Run pre-commit/prek/lefthook/hk hooks against jj bookmark pushes
# https://github.com/mattwilkinsonn/jj-hooks
#
# Ships two identical binaries: jj-hooks (canonical) and jj-hp (shorter alias).
# `jj-hp push` is a drop-in replacement for `jj git push` that runs the
# configured hook runner in an ephemeral git worktree before pushing.
#
# Packaged from prebuilt release tarballs. Update the version + hashes together
# when bumping; the project was re-anchored from the zireael monorepo to this
# standalone repository in v0.3.12.
{
  lib,
  stdenvNoCC,
  autoPatchelfHook,
  stdenv,
  fetchurl,
}: let
  version = "0.6.0";

  sources = {
    x86_64-linux = {
      platform = "linux-x64";
      hash = "sha256-PL9xtMrRjyMtmyg68eyMOrbHP4ZXF7/oJFNtrwBsYhQ=";
    };
    aarch64-linux = {
      platform = "linux-arm64";
      hash = "sha256-dcHEXW7E9kY5nMQVFOrgWwwAGqajxenslYzbnMX4sJI=";
    };
    aarch64-darwin = {
      platform = "darwin-arm64";
      hash = "sha256-NXBXBOnhYYB8lffzO/4YbbLxqVf1tYDfCxEdwMNzyDk=";
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
      url = "https://github.com/mattwilkinsonn/jj-hooks/releases/download/v${version}/jj-hooks-v${version}-${source.platform}.tar.gz";
      hash = source.hash;
    };

    sourceRoot = "jj-hooks-v${version}-${source.platform}";

    dontBuild = true;

    nativeBuildInputs = lib.optionals stdenvNoCC.hostPlatform.isLinux [autoPatchelfHook];
    buildInputs = lib.optionals stdenvNoCC.hostPlatform.isLinux [stdenv.cc.cc.lib];

    installPhase = ''
      runHook preInstall

      install -Dm755 jj-hooks $out/bin/jj-hooks
      install -Dm755 jj-hp $out/bin/jj-hp

      runHook postInstall
    '';

    meta = with lib; {
      description = "Run pre-commit/prek/lefthook/hk hooks against jj bookmark pushes";
      homepage = "https://github.com/mattwilkinsonn/jj-hooks";
      license = licenses.asl20;
      maintainers = [];
      mainProgram = "jj-hp";
      platforms = builtins.attrNames sources;
    };
  }
