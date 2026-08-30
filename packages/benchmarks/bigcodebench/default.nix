# BigCodeBench — practical and rigorous benchmark for code generation with
# diverse function calls and complex instructions (bigcode-project/bigcodebench).
#
# Only the `bigcodebench.generate` console script (code generation against a
# model/backend) is a supported use case here, targeting the "openai"
# backend against local OpenAI-compatible endpoints such as oMLX. The
# `bigcodebench.evaluate` script additionally executes model-generated code
# via a remote Gradio space or E2B sandbox (see gradio-client/e2b removal
# below) and is intentionally out of scope for this package.
{
  lib,
  python3Packages,
  fetchFromGitHub,
  fetchPypi,
}: let
  # A handful of small, pure-Python upstream dependencies aren't packaged in
  # nixpkgs. They have no heavy transitive deps, so build them inline here
  # rather than adding them to the overlay for a single consumer.
  bounded-pool-executor = python3Packages.buildPythonPackage rec {
    pname = "bounded-pool-executor";
    version = "0.0.3";
    pyproject = true;

    src = fetchPypi {
      pname = "bounded_pool_executor";
      inherit version;
      hash = "sha256-4JIiG8OK3lVeEGSDH57YAFgPo0pLbY6d082WFUlif24=";
    };

    build-system = [python3Packages.setuptools];

    doCheck = false;

    meta = {
      description = "BoundedSemaphore for ProcessPoolExecutor & ThreadPoolExecutor";
      homepage = "https://github.com/mowshon/bounded_pool_executor";
      license = lib.licenses.mit;
    };
  };

  tempdir = python3Packages.buildPythonPackage rec {
    pname = "tempdir";
    version = "0.7.1";
    pyproject = true;

    src = fetchPypi {
      inherit pname version;
      hash = "sha256-aJaA7TukzINHpw5n78JQhs6FtTudJKFCCJnFhbv3uo4=";
    };

    build-system = [python3Packages.setuptools];

    doCheck = false;

    meta = {
      description = "Tempdirs are temporary directories, based on tempfile.mkdtemp";
      homepage = "https://bitbucket.org/another_thomas/tempdir";
      license = lib.licenses.mit;
    };
  };

  pqdm = python3Packages.buildPythonPackage rec {
    pname = "pqdm";
    version = "0.2.0";
    pyproject = true;

    src = fetchPypi {
      inherit pname version;
      hash = "sha256-2Z0B/kmNMntEDr/gjBTITg3J7M5hcu+aMflrsar06eM=";
    };

    build-system = [python3Packages.setuptools];

    propagatedBuildInputs =
      [bounded-pool-executor]
      ++ (with python3Packages; [tqdm typing-extensions]);

    doCheck = false;

    meta = {
      description = "A TQDM and concurrent futures wrapper for parallelized progress bars";
      homepage = "https://github.com/niedakh/pqdm";
      license = lib.licenses.mit;
    };
  };
in
  python3Packages.buildPythonApplication rec {
    pname = "bigcodebench";
    version = "0.2.5";
    pyproject = true;

    src = fetchFromGitHub {
      owner = "bigcode-project";
      repo = "bigcodebench";
      tag = "v${version}";
      hash = "sha256-XMq/ojuBkYExtWkx//wB73voADkVXuH153y8pWUusqw=";
    };

    nativeBuildInputs = with python3Packages; [
      setuptools
      setuptools-scm
      pythonRelaxDepsHook
    ];

    # pyproject.toml uses setuptools_scm for dynamic versioning derived from
    # git tags; the fetched source tree has no .git metadata, so pretend it.
    env.SETUPTOOLS_SCM_PRETEND_VERSION = version;

    pythonRelaxDeps = true;

    # vllm is a hard install_requires upstream, but bigcodebench/provider
    # only imports it lazily when backend == "vllm"
    # (see bigcodebench/provider/__init__.py). We only use the "openai"
    # backend against local OpenAI-compatible endpoints (e.g. oMLX), so
    # drop the vllm requirement rather than packaging it.
    #
    # gradio-client and e2b are hard install_requires used only by the
    # `bigcodebench.evaluate` console script (untrusted-code execution via
    # a Gradio space or E2B sandbox) — see bigcodebench/evaluate.py. That
    # entry point is out of scope here (see the package/devenv task
    # comments); dropping them avoids a real build failure with e2b's
    # nixpkgs packaging (version/METADATA mismatch as of the pinned
    # nixpkgs revision) and an otherwise unused heavy dependency.
    pythonRemoveDeps = ["vllm" "gradio-client" "e2b"];

    propagatedBuildInputs = with python3Packages;
      [
        pqdm
        tempdir
      ]
      ++ [
        appdirs
        fire
        multipledispatch
        termcolor
        tqdm
        tree-sitter
        tree-sitter-python
        wget
        transformers
        datasets
        numpy
        rich
        accelerate
        anthropic
        google-genai
        mistralai
        openai
      ];

    doCheck = false;

    meta = {
      description = "Rigorous benchmark for code generation with practical and challenging programming tasks";
      homepage = "https://github.com/bigcode-project/bigcodebench";
      license = lib.licenses.asl20;
    };
  }
