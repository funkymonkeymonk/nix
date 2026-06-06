# MLX model packages fetched from HuggingFace
# Each model is a fixed-output derivation for reproducibility and caching.
{
  lib,
  stdenvNoCC,
  python313Packages,
  ...
}: let
  huggingface-hub = python313Packages.huggingface-hub;
  inherit (builtins) replaceStrings;
in {
  # Fetch an MLX model from HuggingFace as a fixed-output derivation.
  # To compute outputHash:
  #   1. Set outputHash = lib.fakeHash and build
  #   2. Nix will fail with the actual hash — copy it here
  #   3. Rebuild — subsequent builds are cached
  fetchModel = {
    name,
    modelPath,
    outputHash,
  }:
    stdenvNoCC.mkDerivation {
      pname = name;
      version = "0";
      nativeBuildInputs = [huggingface-hub];
      outputHashMode = "recursive";
      outputHashAlgo = "sha256";
      inherit outputHash;
      phases = ["buildPhase" "installPhase"];
      buildPhase = ''
        export HF_HOME="$PWD/.cache"
        ${huggingface-hub}/bin/huggingface-cli download "${modelPath}"
        mkdir -p $out
        cp -r "$HF_HOME/hub/models--$(echo "${modelPath}" | tr '/' '--')/snapshots/"*/* "$out/"
      '';
      installPhase = "true";
      meta = {
        description = "MLX model: ${modelPath}";
        platforms = lib.platforms.darwin;
      };
    };
}
