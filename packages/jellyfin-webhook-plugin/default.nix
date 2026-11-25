{
  lib,
  fetchzip,
  stdenvNoCC,
}: let
  version = "22.0.0.0";
in
  stdenvNoCC.mkDerivation {
    pname = "jellyfin-webhook-plugin";
    inherit version;

    src = fetchzip {
      name = "jellyfin-webhook-plugin-${version}-source";
      url = "https://github.com/jellyfin/jellyfin-plugin-webhook/releases/download/v22/webhook_${version}.zip";
      hash = "sha256-9i5yBwPR4rxkRLlpd+8izHOCejtX28cn4UOJjcS2nY4=";
      stripRoot = false;
    };

    dontUnpack = true;
    dontBuild = true;

    installPhase = ''
      runHook preInstall
      mkdir -p "$out"
      cp -a "$src"/. "$out"/
      runHook postInstall
    '';

    meta = {
      description = "Official Jellyfin plugin for sending webhook notifications";
      homepage = "https://github.com/jellyfin/jellyfin-plugin-webhook";
      license = lib.licenses.gpl3Only;
      platforms = lib.platforms.linux;
    };
  }
