# MLX model packages fetched from HuggingFace
# Uses huggingface-hub CLI (hf download) for reliable CDN downloads.
# curl fails on large files (>1GB) due to HF CDN auth requirements.
{
  lib,
  stdenvNoCC,
  python3Packages,
  cacert,
  ...
}: {
  # Fetch an MLX model from HuggingFace as a fixed-output derivation.
  # To compute outputHash:
  #   1. Set outputHash = lib.fakeSha256 and build
  #   2. Nix will fail with the actual hash — copy it here
  #   3. Rebuild — subsequent builds are cached
  fetchModel = {
    name,
    modelPath,
    outputHash,
    include ? ["*.safetensors" "*.json" "*.jinja"],
    extraHook ? "",
  }:
    stdenvNoCC.mkDerivation {
      pname = name;
      version = "0";
      nativeBuildInputs = [python3Packages.huggingface-hub];
      SSL_CERT_FILE = "${cacert}/etc/ssl/certs/ca-bundle.crt";
      outputHashMode = "recursive";
      outputHashAlgo = "sha256";
      inherit outputHash;
      phases = ["buildPhase" "installPhase"];
      buildPhase = ''
        set -euo pipefail
        echo "Downloading ${modelPath} from HuggingFace..."

        # hf download needs a writable HOME for its cache
        export HOME=$(mktemp -d)

        mkdir -p $out

        ${lib.getExe python3Packages.huggingface-hub} download "${modelPath}" \
          --local-dir "$out" \
          --include "*.safetensors" \
          --include "*.json" \
          --include "*.jinja"

        # Remove HF cache metadata — not deterministic across builds
        rm -rf "$out/.cache"

        echo "Done downloading ${modelPath}."
        ${extraHook}
      '';
      installPhase = "true";
      meta = {
        description = "MLX model: ${modelPath}";
        platforms = lib.platforms.darwin;
      };
    };
}
