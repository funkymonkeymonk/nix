# mlx-audio 0.4.5 — Required by mlx-vlm 0.6.4
{
  lib,
  python3Packages,
  fetchPypi,
}:
python3Packages.buildPythonPackage rec {
  pname = "mlx-audio";
  version = "0.4.5";
  pyproject = true;

  src = fetchPypi {
    pname = "mlx_audio";
    inherit version;
    hash = "sha256-imcGbafAbRZn5fnPws67+HKxNIomU7GaGzz5Vpfktlg=";
  };

  nativeBuildInputs = with python3Packages; [setuptools];
  build-system = with python3Packages; [setuptools];

  dependencies = with python3Packages; [
    huggingface-hub
    miniaudio
    mlx
    mlx-lm
    numpy
    scipy
    sounddevice
    tqdm
    transformers
  ];

  doCheck = false;
  pythonImportsCheck = ["mlx_audio"];

  meta = {
    description = "Text-to-speech and audio processing with MLX";
    homepage = "https://github.com/Blaizzy/mlx-audio";
    license = lib.licenses.mit;
    platforms = lib.platforms.darwin;
  };
}
