# MLX model packages fetched from HuggingFace
# Each model is a fixed-output derivation for reproducibility and caching.
{
  lib,
  stdenvNoCC,
  curl,
  jq,
  gnugrep,
  gnused,
  cacert,
  ...
}: let
in {
  # Fetch an MLX model from HuggingFace as a fixed-output derivation.
  # To compute outputHash:
  #   1. Set outputHash = "" and build
  #   2. Nix will fail with the actual hash — copy it here
  #   3. Rebuild — subsequent builds are cached
  fetchModel = {
    name,
    modelPath,
    outputHash,
    includePattern ? "\\.(safetensors|json)$",
    extraHook ? "",
  }:
    stdenvNoCC.mkDerivation {
      pname = name;
      version = "0";
      nativeBuildInputs = [curl jq gnugrep gnused cacert];
      SSL_CERT_FILE = "${cacert}/etc/ssl/certs/ca-bundle.crt";
      outputHashMode = "recursive";
      outputHashAlgo = "sha256";
      inherit outputHash;
      phases = ["buildPhase" "installPhase"];
      buildPhase = ''
        echo "Fetching file list for ${modelPath}..."
        FILES=$(${curl}/bin/curl -sL "https://huggingface.co/api/models/${modelPath}" | \
          ${jq}/bin/jq --arg pattern "${includePattern}" -r '.siblings[] | select(.rfilename | test($pattern)) | .rfilename')

        mkdir -p $out

        echo "$FILES" | while read -r FILE; do
          [ -z "$FILE" ] && continue
          echo "  Downloading $FILE..."
          ${curl}/bin/curl -sL "https://huggingface.co/${modelPath}/resolve/main/$FILE" \
            -o "$out/$FILE"
        done
        echo "Done."
        ${extraHook}
      '';
      installPhase = "true";
      meta = {
        description = "MLX model: ${modelPath}";
        platforms = lib.platforms.darwin;
      };
    };
}
