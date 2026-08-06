# HuggingFace Lighteval — lightweight and configurable LLM evaluation package.
# Provides a fast alternative to lm-eval with support for leaderboard tasks.
{
  lib,
  python3Packages,
  fetchFromGitHub,
}:
python3Packages.buildPythonApplication rec {
  pname = "lighteval";
  version = "0.13.0";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "huggingface";
    repo = "lighteval";
    tag = "v${version}";
    hash = "sha256-iDkTisvtyBZZFkmuGzRraqf8PUX1G5pZAR+CkbTmJ78=";
  };

  nativeBuildInputs = with python3Packages; [
    setuptools
    wheel
    pythonRelaxDepsHook
  ];

  pythonRelaxDeps = true;

  pythonRemoveDeps = [
    # Heavy extras not packaged in nixpkgs; core local evaluation still works
    "inspect-ai"
    "inspect_ai"
    "latex2sympy2-extended"
    "latex2sympy2_extended"
  ];

  propagatedBuildInputs = with python3Packages; [
    accelerate
    datasets
    numpy
    pyyaml
    requests
    torch
    transformers
    # API / local endpoint support
    openai
    anthropic
    litellm
    typer
    rich
    # Task dependencies
    scipy
    scikit-learn
    sentencepiece
    protobuf
    ninja
    # Metrics
    sacrebleu
    rouge-score
    nltk
    # Other common deps
    huggingface-hub
    tokenizers
    safetensors
    filelock
    fsspec
    # Metrics / utils
    gitpython
    termcolor
    colorlog
    aenum
    pycountry
    langcodes
    pytablewriter
  ];

  # inspect-ai is an optional extended-task backend; guard the import and the
  # CLI registration so the tool still works when inspect-ai is not installed.
  postPatch = ''
        substituteInPlace src/lighteval/__main__.py \
          --replace-fail "import lighteval.main_inspect" "try:
        import lighteval.main_inspect
        HAS_INSPECT = True
    except ModuleNotFoundError:
        HAS_INSPECT = False" \
          --replace-fail "app.command(rich_help_panel=\"Evaluation Backends\")(lighteval.main_inspect.eval)" "if HAS_INSPECT:
        app.command(rich_help_panel=\"Evaluation Backends\")(lighteval.main_inspect.eval)" \
          --replace-fail "app.command(rich_help_panel=\"EvaluationUtils\")(lighteval.main_inspect.bundle)" "if HAS_INSPECT:
        app.command(rich_help_panel=\"EvaluationUtils\")(lighteval.main_inspect.bundle)"
  '';

  doCheck = false;

  meta = {
    description = "A lightweight and configurable evaluation package for LLMs";
    homepage = "https://github.com/huggingface/lighteval";
    license = lib.licenses.mit;
  };
}
