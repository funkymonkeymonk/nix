# OpenAI Evals — OpenAI's framework for evaluating LLMs and LLM systems via
# the `oaieval`/`oaievalset` CLIs, targeting any OpenAI-compatible endpoint
# (e.g. oMLX).
# Upstream: https://github.com/openai/evals (PyPI: `evals`).
#
# Scoping decision: upstream's pyproject.toml declares several dependencies
# that are only imported lazily by specific, optional `elsuite` evals or
# provider integrations, never by the `oaieval`/`oaievalset` CLIs or the core
# registry/eval-running machinery:
#   - chess, gymnasium, playwright: only used by specific elsuite evals
#     (cant_do_that_anymore, hr_ml_agent_bench, multistep_web_tasks) that are
#     out of scope for local OpenAI-compatible-endpoint evaluation here.
#   - docker: only used by evals that sandbox-execute model-generated code
#     in a container; out of scope (see bigcodebench's similar exclusion of
#     untrusted-code execution).
#   - langchain, snowflake-connector-python, spacy-universal-sentence-encoder:
#     optional provider/logging/metric integrations (Snowflake result
#     logging, a LangChain-backed solver, a spaCy-based similarity metric),
#     all imported lazily inside the specific functions/classes that need
#     them (see evals/utils/snowflake.py) rather than at module import time.
#   - nltk: declared but unused by anything on the core CLI import path.
# Dropping these keeps the package buildable while still supporting the
# `oaieval`/`oaievalset` entry points against local endpoints for the
# majority of registry evals (basic, model-graded, coding, etc).
{
  lib,
  python3Packages,
  fetchFromGitHub,
}:
python3Packages.buildPythonApplication rec {
  pname = "openai-evals";
  version = "3.0.1";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "openai";
    repo = "evals";
    tag = version;
    hash = "sha256-oBoPeOdkXitjcyRBopnNeSiRFqo1FFe8eA7yIy4Hrrk=";
  };

  nativeBuildInputs = with python3Packages; [
    setuptools
    wheel
    pythonRelaxDepsHook
  ];

  pythonRelaxDeps = true;

  pythonRemoveDeps = [
    "chess"
    "docker"
    "gymnasium"
    "langchain"
    "nltk"
    "playwright"
    "snowflake-connector-python"
    "spacy-universal-sentence-encoder"
  ];

  propagatedBuildInputs = with python3Packages; [
    aiolimiter
    anthropic
    backoff
    beartype
    blobfile
    dacite
    datasets
    evaluate
    filelock
    fire
    flask
    google-generativeai
    jiwer
    langdetect
    lz4
    matplotlib
    mock
    mypy
    networkx
    numexpr
    numpy
    openai
    pandas
    pydantic
    pytest
    pyyaml
    sacrebleu
    seaborn
    statsmodels
    termcolor
    tiktoken
    tqdm
    types-pyyaml
    types-tqdm
    zstandard
  ];

  pythonImportsCheck = ["evals" "evals.cli.oaieval" "evals.cli.oaievalset"];

  # evals/registry.py instantiates an OpenAI() client at module import time
  # (`client = OpenAI(api_key=os.environ.get("OPENAI_API_KEY"))`), which
  # raises unless an API key is present in the environment — even just to
  # import the module, before any network call is made. Set a dummy value
  # so pythonImportsCheck (and any other bare `import evals`) succeeds; the
  # real key/endpoint is supplied at runtime via OPENAI_API_KEY/
  # OPENAI_BASE_URL (see the benchmark:openai-evals devenv task).
  env.OPENAI_API_KEY = "sk-nix-build-dummy";

  # Upstream's test suite requires network access and live model API keys.
  doCheck = false;

  meta = {
    description = "OpenAI's framework for evaluating LLMs and LLM systems";
    homepage = "https://github.com/openai/evals";
    license = lib.licenses.mit;
    mainProgram = "oaieval";
  };
}
