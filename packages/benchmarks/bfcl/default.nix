# Berkeley Function Calling Leaderboard (BFCL) — evaluates LLM function/tool
# calling ability against local OpenAI-compatible endpoints (e.g. vllm-mlx).
# Upstream: https://github.com/ShishirPatil/gorilla/tree/main/berkeley-function-call-leaderboard
# Distributed on PyPI as `bfcl_eval` (careful: the unrelated `bfcl` PyPI
# project is a different package).
#
# Scoping decision: upstream depends on several provider SDKs that are either
# missing from nixpkgs (qwen-agent, writer-sdk) or whose nixpkgs packaging is
# incompatible with what bfcl_eval expects (mistralai — nixpkgs' build is
# missing the top-level `Mistral` client class; tree-sitter-java has no
# nixpkgs python binding at all; tree-sitter-javascript's nixpkgs version
# uses a newer, incompatible `tree_sitter` API). Those provider-specific
# handlers are stubbed out (see postPatch) so the package still builds and
# the CLI still works for the categories that matter for this devenv's use
# case: evaluating locally-hosted / OpenAI-compatible models (like vllm-mlx)
# against the Python-based single-turn and multi-turn test categories.
# `simple_java`, `simple_javascript`, `memory_vector`, and any
# Mistral/Qwen-agent/Writer-backed models are therefore NOT supported by this
# build (sentence-transformers/faiss-cpu, needed only by memory_vector, are
# dropped too since nixpkgs' sentence-transformers pulls in a phonemizer ->
# dlinfo dependency chain that's marked broken on Darwin).
{
  lib,
  python3Packages,
  fetchPypi,
}:
python3Packages.buildPythonApplication rec {
  pname = "bfcl-eval";
  version = "2026.3.23";
  pyproject = true;

  src = fetchPypi {
    pname = "bfcl_eval";
    inherit version;
    hash = "sha256-SjhpZzch+lm+k9j1XKktaatXlwWK7XkhScatr9oGS8E=";
  };

  # Upstream uses setuptools-scm with dynamic versioning derived from git
  # tags. The PyPI sdist has no .git metadata, so pretend the version to
  # avoid falling back to "0.0.0.dev0".
  env.SETUPTOOLS_SCM_PRETEND_VERSION = version;

  nativeBuildInputs = with python3Packages; [
    setuptools
    setuptools-scm
    wheel
    pythonRelaxDepsHook
  ];

  build-system = with python3Packages; [
    setuptools
    setuptools-scm
    wheel
  ];

  pythonRelaxDeps = true;

  # Provider SDKs not packaged in nixpkgs (or incompatible with the pinned
  # API upstream expects) — the corresponding handlers are stubbed in
  # postPatch below so the rest of the package still imports and works.
  # sentence-transformers/faiss-cpu are dropped too: they're only used by
  # the memory_vector multi-turn test category (dynamically imported by
  # module path, never eagerly), and nixpkgs' sentence-transformers pulls
  # in phonemizer -> dlinfo, which is marked broken on Darwin.
  pythonRemoveDeps = [
    "mistralai"
    "qwen-agent"
    "writer-sdk"
    "tree_sitter"
    "tree-sitter-java"
    "tree-sitter-javascript"
    "sentence-transformers"
    "faiss-cpu"
  ];

  propagatedBuildInputs = with python3Packages; [
    requests
    tqdm
    numpy
    pandas
    huggingface-hub
    pydantic
    python-dotenv
    openai
    anthropic
    cohere
    typer
    tabulate
    # doCheck disabled: datamodel-code-generator's own test suite has a
    # flaky/broken assertion on this platform (extra blank line in
    # generated output) that isn't relevant to bfcl-eval's usage of it.
    (datamodel-code-generator.overridePythonAttrs (_: {doCheck = false;}))
    google-genai
    mpmath
    tenacity
    overrides
    boto3
    beautifulsoup4
    html2text
    rank-bm25
    google-search-results
    networkx
    filelock
    # Needed at runtime by the local-inference / remote-endpoint handler
    # (base_oss_handler.py) to load the model's tokenizer/config so prompt
    # formatting and context-length checks work against endpoints like
    # vllm-mlx.
    transformers
  ];

  postPatch = ''
    # mistralai: nixpkgs' build of the client-python package is missing the
    # top-level `Mistral` client class this handler needs. qwen-agent and
    # writer-sdk (writerai) aren't packaged in nixpkgs at all. Stub all three
    # handler imports so bfcl_eval.constants.model_config still imports
    # cleanly; the corresponding provider models are simply unavailable.
    substituteInPlace bfcl_eval/constants/model_config.py \
      --replace-fail \
        "from bfcl_eval.model_handler.api_inference.mistral import MistralHandler" \
        "MistralHandler = None" \
      --replace-fail \
        "from bfcl_eval.model_handler.api_inference.qwen import (
        QwenAgentNoThinkHandler,
        QwenAgentThinkHandler,
        QwenAPIHandler,
    )" \
        "QwenAgentNoThinkHandler = QwenAgentThinkHandler = QwenAPIHandler = None" \
      --replace-fail \
        "from bfcl_eval.model_handler.api_inference.writer import WriterHandler" \
        "WriterHandler = None"

    # tree-sitter-java has no nixpkgs python binding, and nixpkgs'
    # tree-sitter-javascript is built against a newer, incompatible
    # tree_sitter API (Language()/Parser()/Node.sexp() signatures all
    # changed upstream). Guard both parsers so the module still imports;
    # simple_java / simple_javascript test categories are unsupported.
    substituteInPlace bfcl_eval/model_handler/parser/java_parser.py \
      --replace-fail \
        'from tree_sitter import Language, Parser
    import tree_sitter_java

    JAVA_LANGUAGE = Language(tree_sitter_java.language(), "java")

    parser = Parser()
    parser.set_language(JAVA_LANGUAGE)


    def parse_java_function_call(source_code):' \
        'def parse_java_function_call(source_code):
        raise ModuleNotFoundError(
            "tree-sitter-java is not packaged in this build of bfcl-eval; "
            "Java test categories are unsupported."
        )'

    substituteInPlace bfcl_eval/model_handler/parser/js_parser.py \
      --replace-fail \
        'from tree_sitter import Language, Parser
    import tree_sitter_javascript

    JS_LANGUAGE = Language(tree_sitter_javascript.language(), "javascript")

    parser = Parser()
    parser.set_language(JS_LANGUAGE)


    def parse_javascript_function_call(source_code):' \
        'def parse_javascript_function_call(source_code):
        raise ModuleNotFoundError(
            "tree-sitter-javascript is not usable in this build of bfcl-eval "
            "(nixpkgs ships an API-incompatible version); JavaScript test "
            "categories are unsupported."
        )'
  '';

  pythonImportsCheck = ["bfcl_eval"];

  # Upstream has no test suite distributed with the sdist, and the full
  # test suite requires network access / live model API keys anyway.
  doCheck = false;

  meta = {
    description = "Berkeley Function Calling Leaderboard (BFCL) — function/tool-calling evaluation for LLMs";
    homepage = "https://github.com/ShishirPatil/gorilla/tree/main/berkeley-function-call-leaderboard";
    license = lib.licenses.asl20;
    mainProgram = "bfcl";
  };
}
