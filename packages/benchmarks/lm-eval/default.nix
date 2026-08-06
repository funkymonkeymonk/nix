# EleutherAI LM Evaluation Harness — backend for HuggingFace Open LLM Leaderboard
# Supports evaluating local API servers (OpenAI-compatible) and HuggingFace models.
{
  lib,
  python3Packages,
  fetchFromGitHub,
}:
python3Packages.buildPythonApplication rec {
  pname = "lm-eval";
  version = "0.4.10";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "EleutherAI";
    repo = "lm-evaluation-harness";
    tag = "v${version}";
    hash = "sha256-+fVLpJ/wzFyQJkdlHTirTNrtWg7Vn26kU0OV4+oDJXA=";
  };

  nativeBuildInputs = with python3Packages; [
    setuptools
    wheel
    pythonRelaxDepsHook
  ];

  pythonRelaxDeps = true;

  propagatedBuildInputs = with python3Packages; [
    # Core dependencies
    accelerate
    datasets
    evaluate
    jsonlines
    numpy
    peft
    pybind11
    pytablewriter
    pyyaml
    regex
    requests
    sacrebleu
    scikit-learn
    scipy
    sentencepiece
    sqlitedict
    torch
    tqdm
    transformers
    zstandard
    # API backends (local OpenAI/Anthropic-compatible servers)
    openai
    anthropic
    tiktoken
    # Common task deps
    einops
    bitsandbytes
    optimum
    rouge-score
    word2number
    more-itertools
  ];

  # Skip network-dependent tests
  doCheck = false;

  meta = {
    description = "A framework for few-shot evaluation of language models";
    homepage = "https://github.com/EleutherAI/lm-evaluation-harness";
    license = lib.licenses.mit;
  };
}
