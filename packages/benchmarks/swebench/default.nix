# SWE-bench — benchmark for evaluating LMs on real-world software
# engineering (GitHub issue/PR-derived) tasks. Upstream:
# https://github.com/swe-bench/SWE-bench, distributed on PyPI as `swebench`.
#
# Scoping decision: the modern `swebench` CLI has four subcommand groups:
#   - `swebench dataset` (build/check/diff/collect/push) — curates task repos
#     into published datasets. No Docker involved.
#   - `swebench report` — re-grades a finished run from its saved logs
#     ("without starting containers", per its own --help). No Docker
#     involved, but it operates on logs that were themselves produced by a
#     prior Docker-based `swebench eval` run.
#   - `swebench eval` — grades gold/model predictions by building/pulling a
#     Docker image per task instance and running the repo's real test suite
#     inside a container.
#   - `swebench images` (build/check/clean/push) — builds/pulls/inspects
#     those same per-instance Docker images ahead of an evaluation.
#
# `eval` and `images` both hard-require a running Docker daemon (they call
# `docker.from_env()`/build images directly) to do anything useful, and are
# the exact "spinning up Docker containers to run repo test suites" case
# this devenv package is intentionally not attempting. `dataset` and
# `report` are packaged and usable; `eval`/`images` are still present on the
# `swebench` binary (upstream doesn't split them into separate packages) but
# will simply fail the way they would for anyone without Docker installed.
#
# Also intentionally out of scope: upstream's legacy, pre-CLI
# `swebench.inference.run_api`/`run_llama` scripts (a "prediction
# generation against a model" path from the original 2023 paper). They are
# not exposed via the modern `swebench` console script, are hard-coded to a
# fixed table of OpenAI/Anthropic model names and context limits (not
# generic OpenAI-compatible endpoints like vllm-mlx), and the package's
# "inference" extra they'd need pulls in torch/triton/flash_attn, which
# don't build sensibly for a CPU-only aarch64-darwin devenv. Generating
# predictions against a local model is left to an external SWE-bench-
# compatible coding agent (SWE-agent, mini-swe-agent, OpenHands, etc.)
# pointed at the local vllm-mlx OpenAI-compatible endpoint; its output feeds
# `swebench eval`, which then requires Docker outside this devenv.
{
  lib,
  python3Packages,
  fetchPypi,
}:
python3Packages.buildPythonApplication rec {
  pname = "swebench";
  version = "5.0.2";
  pyproject = true;

  src = fetchPypi {
    inherit pname version;
    hash = "sha256-+q57Ewe4GI6ELnjvWCbPDWT6eEhq3EHjQU+VM7ng1+s=";
  };

  # pyproject.toml resolves the version dynamically from
  # swebench.__version__ (a plain module attribute, not setuptools-scm), so
  # no SETUPTOOLS_SCM_PRETEND_VERSION dance is needed here.
  build-system = with python3Packages; [setuptools];

  nativeBuildInputs = with python3Packages; [pythonRelaxDepsHook];

  pythonRelaxDeps = true;

  # `pre-commit` is declared in pyproject.toml's install_requires but never
  # imported anywhere in swebench's own source (verified against the 5.0.2
  # sdist) -- almost certainly a leftover from upstream's own dev-tooling
  # setup rather than a real runtime dependency. Dropping it also sidesteps
  # that nixpkgs only ships `pre-commit` as a top-level CLI package, not a
  # `python3Packages` library.
  pythonRemoveDeps = ["pre-commit"];

  # Core (unconditional) install_requires only. The "datasets"/"inference"
  # extras (torch, transformers, tiktoken, flash_attn, ...) are not needed
  # for the `dataset`/`report` subcommands this package targets and are
  # dropped per the scoping decision above.
  propagatedBuildInputs = with python3Packages; [
    beautifulsoup4
    chardet
    datasets
    docker
    ghapi
    gitpython
    modal
    python-dotenv
    pyyaml
    requests
    rich
    typer
    tenacity
    tqdm
    unidiff
  ];

  pythonImportsCheck = ["swebench"];

  # Upstream's test suite needs network access and, for most cases, a
  # running Docker daemon (it exercises `swebench eval`); not runnable in
  # the Nix build sandbox.
  doCheck = false;

  meta = {
    description = "SWE-bench — benchmark for evaluating LMs on real-world GitHub issue/PR software engineering tasks (dataset curation and log-based re-grading only; Docker-based eval/images are out of scope)";
    homepage = "https://github.com/swe-bench/SWE-bench";
    license = lib.licenses.mit;
    mainProgram = "swebench";
  };
}
