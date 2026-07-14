# vllm-mlx — vLLM-style inference server for Apple Silicon
# Packaged from PyPI with all dependencies from nixpkgs.
# Gradio is removed (UI optional). mlx-vlm comes from the overlay
# at version 0.6.4 because nixpkgs 0.4.4 lacks Gemma 4 support.
{
  lib,
  python3Packages,
  fetchPypi,
  mlx-embeddings,
  mlx-vlm,
}:
python3Packages.buildPythonApplication rec {
  pname = "vllm-mlx";
  version = "0.4.0";
  pyproject = true;

  src = fetchPypi {
    pname = "vllm_mlx";
    inherit version;
    hash = "sha256-zNrawBjozyxlNSl+IEp9vbHvcpnQ6AE0ONIWl3Dne9o=";
  };

  nativeBuildInputs = with python3Packages; [
    setuptools
    wheel
    pythonRelaxDepsHook
  ];

  pythonRemoveDeps = [
    "gradio"
    "opencv-python"
  ];

  propagatedBuildInputs = with python3Packages;
    [
      mlx
      mlx-lm
      transformers
      tokenizers
      huggingface-hub
      numpy
      pillow
      tqdm
      pyyaml
      requests
      tabulate
      opencv4
      torchvision
      torch
      psutil
      fastapi
      starlette
      uvicorn
      prometheus-client
      mcp
      jsonschema
      lm-format-enforcer
      typing-extensions
      openai
      httpx
      aiohttp
      tiktoken
    ]
    ++ [mlx-embeddings mlx-vlm];

  # Patch bind_generation_streams to use set_generation_stream() when available,
  # instead of replacing the function with a raw Stream object via setattr.
  # Our patched mlx-lm 0.31.3 makes generation_stream a function with a
  # thread-local backing; clobbering it with setattr breaks inference.
  postPatch = ''
    substituteInPlace vllm_mlx/mlx_streams.py \
      --replace-fail 'if hasattr(module, "generation_stream"):' 'if hasattr(module, "set_generation_stream"):' \
      --replace-fail 'setattr(module, "generation_stream", default_stream)' 'module.set_generation_stream(default_stream)'
  '';

  # Darwin-only: MLX is Apple Silicon only
  meta = with lib; {
    description = "vLLM-like inference server for Apple Silicon with MLX";
    homepage = "https://github.com/waybarrios/vllm-mlx";
    license = licenses.asl20;
    platforms = platforms.darwin;
    mainProgram = "vllm-mlx";
  };
}
