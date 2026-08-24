# OpenAI HumanEval + Google Research MBPP — lightweight Python
# code-generation benchmarks, packaged together.
#
# Scoping note: HumanEval ships an official pip-installable evaluation
# harness (this repo: openai/human-eval), so it is wrapped exactly like
# lm-eval/lighteval below (buildPythonApplication over a fetchFromGitHub
# source). MBPP (google-research/mbpp) has no upstream Python package at
# all -- just a JSONL dataset file and a README -- so there is nothing
# equivalent to wrap. Both benchmarks are small and share the same
# "generate a completion, execute it, check the asserts" evaluation model,
# so this single derivation:
#   - installs HumanEval's `evaluate_functional_correctness` CLI unchanged
#   - vendors both datasets (HumanEval.jsonl.gz from the fetched source,
#     mbpp.jsonl via a pinned fetchurl) under $out/share/
#   - adds a small stdlib-only `mbpp-eval` CLI that mirrors HumanEval's
#     sandboxed pass@1 scoring for MBPP's `test_list` (plain assert
#     statements) format, since no reference implementation exists upstream
{
  lib,
  python3Packages,
  fetchFromGitHub,
  fetchurl,
  makeWrapper,
}:
python3Packages.buildPythonApplication rec {
  pname = "humaneval-mbpp";
  version = "2025-01-17";
  format = "setuptools";

  src = fetchFromGitHub {
    owner = "openai";
    repo = "human-eval";
    rev = "6d43fb980f9fee3c892a914eda09951f772ad10d";
    hash = "sha256-HqClZYzA2i9yio/ljv3EJm8bgw3t6kLTPdKmz5LeFf0=";
  };

  # MBPP dataset, pinned to a specific google-research commit for
  # reproducibility (the mbpp/ directory itself is never rewritten upstream,
  # but pinning avoids depending on a moving `master` ref).
  mbppDataset = fetchurl {
    url = "https://raw.githubusercontent.com/google-research/google-research/e20eb00d074cdb569ee27318f112ea1e85bbb98f/mbpp/mbpp.jsonl";
    hash = "sha256-zPZM6unFQDv1CgRMttUFv9Kilj7lgzi6Jo/WW+q5Kp8=";
  };

  nativeBuildInputs = with python3Packages; [
    setuptools
    makeWrapper
  ];

  propagatedBuildInputs = with python3Packages; [
    fire
    numpy
    tqdm
  ];

  # Upstream setup.py parses requirements.txt via pkg_resources at build
  # time, which is fragile (pkg_resources is deprecated/absent in newer
  # setuptools) and redundant -- propagatedBuildInputs above already
  # provides the same three runtime deps declaratively.
  #
  # It also declares its console_scripts entry point as a bare module
  # (no `:callable`) -- a legacy easy-install convention that modern pip's
  # `installer` backend rejects outright. Pointing the entry point at
  # `:main` requires human_eval/evaluate_functional_correctness.py's
  # unconditional `sys.exit(main())` to be guarded by
  # `if __name__ == "__main__":` -- without that guard, multiprocessing's
  # spawn start method (default on macOS/Windows) re-imports this module in
  # every worker process and re-runs the whole CLI recursively, deadlocking
  # `multiprocessing.Manager()`. This is a latent upstream bug that only
  # manifests on spawn-based platforms; the guard is the standard, correct
  # fix and has no effect on Linux (fork-based) behavior.
  postPatch = ''
        substituteInPlace setup.py \
          --replace-fail 'import pkg_resources
    from setuptools import setup, find_packages' \
          'from setuptools import setup, find_packages' \
          --replace-fail 'install_requires=[
            str(r)
            for r in pkg_resources.parse_requirements(
                open(os.path.join(os.path.dirname(__file__), "requirements.txt"))
            )
        ],' \
          'install_requires=[],' \
          --replace-fail '"evaluate_functional_correctness = human_eval.evaluate_functional_correctness",' \
          '"evaluate_functional_correctness = human_eval.evaluate_functional_correctness:main",'

        substituteInPlace human_eval/evaluate_functional_correctness.py \
          --replace-fail 'sys.exit(main())' \
          'if __name__ == "__main__":
        sys.exit(main())'
  '';

  # human-eval's own test suite executes untrusted generated code by design
  # (it is a functional-correctness *harness*, not a library with unit
  # tests) -- there is nothing meaningful to run under `nix build`'s
  # sandbox, and upstream ships no test directory besides example fixtures.
  doCheck = false;

  postInstall = ''
    # Vendor both benchmark datasets under $out/share so devenv tasks and
    # downstream tooling can locate them without re-fetching.
    mkdir -p $out/share/humaneval $out/share/mbpp
    cp data/HumanEval.jsonl.gz $out/share/humaneval/
    cp ${mbppDataset} $out/share/mbpp/mbpp.jsonl

    # mbpp-eval: stdlib-only scorer for MBPP's assert-based test_list format.
    # Wrapped with the same interpreter the package was built against so it
    # always has a working `python3` regardless of what's on $PATH.
    install -Dm755 ${./mbpp_eval.py} $out/libexec/humaneval-mbpp/mbpp_eval.py
    makeWrapper ${python3Packages.python.interpreter} $out/bin/mbpp-eval \
      --add-flags $out/libexec/humaneval-mbpp/mbpp_eval.py \
      --set-default MBPP_DATASET $out/share/mbpp/mbpp.jsonl
  '';

  meta = {
    description = "OpenAI HumanEval functional-correctness harness bundled with the MBPP dataset and a matching assert-based scorer";
    homepage = "https://github.com/openai/human-eval";
    license = lib.licenses.mit;
  };
}
