# mlx-embeddings — embedding models on Apple Silicon via MLX
# Small companion package required by vllm-mlx.
{
  lib,
  python3Packages,
  fetchPypi,
}:
python3Packages.buildPythonApplication rec {
  pname = "mlx-embeddings";
  version = "0.1.0";
  pyproject = true;

  src = fetchPypi {
    pname = "mlx_embeddings";
    inherit version;
    hash = "sha256-+AweG+Jv970isVwfukzAOv1EyG4ApDG1+nX/11AK/7E=";
  };

  nativeBuildInputs = with python3Packages; [
    setuptools
  ];

  propagatedBuildInputs = with python3Packages; [
    mlx
    mlx-vlm
    transformers
    huggingface-hub
  ];

  # Darwin-only: MLX is Apple Silicon only
  meta = with lib; {
    description = "Vision and language embedding models on Apple Silicon via MLX";
    homepage = "https://github.com/Blaizzy/mlx-embeddings";
    license = licenses.gpl3;
    platforms = platforms.darwin;
    mainProgram = "mlx_embeddings";
  };
}
