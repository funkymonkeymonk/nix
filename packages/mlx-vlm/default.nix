# mlx-vlm 0.6.4 — Required by vllm-mlx 0.4.0 for Gemma 4 support
# nixpkgs has 0.4.4 which lacks ScaledLinear quantization needed for Gemma 4.
{
  lib,
  python3Packages,
  fetchPypi,
  mlx-audio,
}:
python3Packages.buildPythonPackage rec {
  pname = "mlx-vlm";
  version = "0.6.4";
  pyproject = true;

  src = fetchPypi {
    pname = "mlx_vlm";
    inherit version;
    hash = "sha256-KpEWkq7cOGGuJvQFexwF3Lmr+5VNUBI98+9j6rDFjik=";
  };

  nativeBuildInputs = with python3Packages; [pythonRelaxDepsHook setuptools];
  pythonRelaxDeps = ["transformers"];
  pythonRemoveDeps = ["opencv-python"];

  build-system = with python3Packages; [setuptools];

  dependencies = with python3Packages;
    [
      mlx
      mlx-lm
      transformers
      pillow
      requests
      tqdm
      numpy
      opencv4
      fastapi
      uvicorn
      starlette
      python-multipart
      pyyaml
      datasets
      huggingface-hub
      tokenizers
      llguidance
      miniaudio
    ]
    ++ [mlx-audio];

  # Patch: allow loading models with missing weights (e.g. OptiQ quants
  # where vision weights are in a separate sidecar). Text-only inference
  # works fine when vision weights are absent.
  postPatch = ''
    sed -i 's/model.load_weights(list(weights.items()), strict=strict)/model.load_weights(list(weights.items()), strict=False)/' mlx_vlm/utils.py
  '';

  # Tests require network access to download models
  doCheck = false;

  pythonImportsCheck = ["mlx_vlm"];

  meta = {
    description = "Vision LLMs on Apple Silicon with MLX";
    homepage = "https://github.com/Blaizzy/mlx-vlm";
    license = lib.licenses.mit;
    platforms = lib.platforms.darwin;
  };
}
