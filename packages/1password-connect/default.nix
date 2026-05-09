# 1Password Connect Server package
# Provides REST API for accessing 1Password secrets
# https://developer.1password.com/docs/connect
{
  lib,
  stdenv,
  fetchurl,
  installShellFiles,
}: let
  version = "1.7.3";

  # Platform-specific binary names and hashes
  platforms = {
    aarch64-darwin = {
      name = "connect_darwin_arm64";
      hash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="; # Placeholder
    };
    x86_64-darwin = {
      name = "connect_darwin_amd64";
      hash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="; # Placeholder
    };
    x86_64-linux = {
      name = "connect_linux_amd64";
      hash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="; # Placeholder
    };
    aarch64-linux = {
      name = "connect_linux_arm64";
      hash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="; # Placeholder
    };
  };

  platform = platforms.${stdenv.hostPlatform.system} or (throw "Unsupported system: ${stdenv.hostPlatform.system}");
in
  stdenv.mkDerivation {
    pname = "1password-connect";
    inherit version;

    src = fetchurl {
      url = "https://cache.agilebits.com/dist/1P/op/pkg/v${version}/op_connect_server_v${version}_zip.zip";
      hash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="; # We'll need to prefetch
    };

    nativeBuildInputs = [installShellFiles];

    sourceRoot = ".";

    installPhase = ''
      runHook preInstall

      # Extract the appropriate binary for the platform
      mkdir -p $out/bin

      # The zip contains all platform binaries
      if [[ -f "${platform.name}/op-connect-api" ]]; then
        cp "${platform.name}/op-connect-api" $out/bin/
        cp "${platform.name}/op-connect-sync" $out/bin/
      else
        # Try flat structure
        cp op-connect-api $out/bin/ 2>/dev/null || true
        cp op-connect-sync $out/bin/ 2>/dev/null || true
      fi

      chmod +x $out/bin/*

      runHook postInstall
    '';

    meta = with lib; {
      description = "1Password Connect Server - REST API for accessing 1Password secrets";
      homepage = "https://developer.1password.com/docs/connect";
      license = licenses.unfree; # 1Password proprietary license
      sourceProvenance = with sourceTypes; [binaryNativeCode];
      maintainers = [];
      platforms = ["aarch64-darwin" "x86_64-darwin" "x86_64-linux" "aarch64-linux"];
      mainProgram = "op-connect-api";
    };
  }
