# ModelScope EvalScope — lightweight LLM/VLM evaluation framework with
# OpenAI-compatible API support for evaluating local model servers.
{
  lib,
  python3Packages,
  fetchFromGitHub,
}:
python3Packages.buildPythonApplication rec {
  pname = "evalscope";
  version = "1.10.0";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "modelscope";
    repo = "evalscope";
    tag = "v${version}";
    hash = "sha256-iDqWexTFfF7mmmkiMysMeMc9KjeTYvzYaJusqBXSlVE=";
  };

  nativeBuildInputs = with python3Packages; [
    setuptools
    wheel
    pythonRelaxDepsHook
  ];

  pythonRelaxDeps = true;

  pythonRemoveDeps = [
    # Optional extras not packaged in nixpkgs; core Native-backend evaluation
    # (multiple-choice / exact-match benchmarks like arc, mmlu, gsm8k) does
    # not need these at import time thanks to evalscope's lazy metrics module.
    "latex2sympy2-extended"
    "latex2sympy2_extended"
    "rouge-chinese"
    "rouge_chinese"
    "zhconv"
    # PyPI distribution name mismatch: upstream requires "dotenv" but the
    # nixpkgs (and PyPI) package providing this module is "python-dotenv".
    # Still included via propagatedBuildInputs below; just drop the
    # unsatisfiable metadata requirement check.
    "dotenv"
  ];

  propagatedBuildInputs = with python3Packages; [
    # Core dependencies (requirements/framework.txt)
    aiohttp
    colorlog
    docstring-parser
    python-dotenv
    editdistance
    jieba
    jinja2
    jsonlines
    jsonschema
    litellm
    markdown
    modelscope
    datasets
    more-itertools
    nltk
    openai
    overrides
    pandas
    pillow
    plotly
    pydantic
    pylatexenc
    pyyaml
    requests
    rich
    rouge-score
    sacrebleu
    sympy
    tabulate
    tqdm
    transformers
    word2number
  ];

  # Skip network-dependent tests
  doCheck = false;

  # Sanity check the entry point still resolves without the optional
  # (unpackaged) extras installed.
  pythonImportsCheck = ["evalscope.cli.cli"];

  meta = {
    description = "Lightweight LLM/VLM evaluation framework supporting OpenAI-compatible local API servers";
    homepage = "https://github.com/modelscope/evalscope";
    license = lib.licenses.asl20;
  };
}
