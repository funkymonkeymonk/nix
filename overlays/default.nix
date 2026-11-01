# Custom package overlays
{inputs ? {}}: final: _prev:
{
  # WHY: pins RTK and installs its rewrite hooks used by developer roles.
  # REMOVE WHEN: nixpkgs provides a version with the same CLI and hook files.
  rtk = final.callPackage ../packages/rtk {};
  # WHY: the yaks CLI is used for repository task tracking and is packaged here.
  # REMOVE WHEN: nixpkgs packages a compatible yaks release or task tracking stops using it.
  yaks = final.callPackage ../packages/yaks {};
  # WHY: jj push delegates to jj-hp so repository hooks run before bookmarks are pushed.
  # REMOVE WHEN: the hook workflow is removed or an equivalent jj-native/nixpkgs tool replaces it.
  jj-hooks = final.callPackage ../packages/jj-hooks {};
  # WHY: supplies the pinned Apple-Silicon Lume VM binary used by local VM workflows.
  # REMOVE WHEN: nixpkgs provides a compatible Apple-Silicon Lume package.
  lume = final.callPackage ../packages/lume {};
  # WHY: provides the pinned lm-evaluation-harness CLI used by benchmark tasks.
  # REMOVE WHEN: nixpkgs provides a compatible package or this benchmark is retired.
  lm-eval = final.callPackage ../packages/benchmarks/lm-eval {};
  # WHY: provides the pinned Hugging Face LightEval CLI used by benchmark tasks.
  # REMOVE WHEN: nixpkgs provides a compatible package or this benchmark is retired.
  lighteval = final.callPackage ../packages/benchmarks/lighteval {};
  # WHY: packages the Berkeley Function-Calling benchmark CLI and its data interface.
  # REMOVE WHEN: nixpkgs provides a compatible package or this benchmark is retired.
  bfcl-eval = final.callPackage ../packages/benchmarks/bfcl {};
  # WHY: packages BigCodeBench and its required Python entry points for benchmark runs.
  # REMOVE WHEN: nixpkgs provides a compatible package or this benchmark is retired.
  bigcodebench = final.callPackage ../packages/benchmarks/bigcodebench {};
  # WHY: provides the pinned ModelScope EvalScope CLI for benchmark tasks.
  # REMOVE WHEN: nixpkgs provides a compatible package or this benchmark is retired.
  evalscope = final.callPackage ../packages/benchmarks/evalscope {};
  # WHY: provides the pinned OpenAI Evals CLI used by local evaluation tasks.
  # REMOVE WHEN: nixpkgs provides a compatible package or this benchmark is retired.
  openai-evals = final.callPackage ../packages/benchmarks/openai-evals {};
  # WHY: packages HumanEval and MBPP harnesses/datasets for local benchmark runs.
  # REMOVE WHEN: nixpkgs provides compatible harnesses and datasets or benchmarks are retired.
  humaneval-mbpp = final.callPackage ../packages/benchmarks/humaneval-mbpp {};
  # WHY: pins the MLX Audio package used by Apple-Silicon inference tools.
  # REMOVE WHEN: nixpkgs provides a compatible MLX Audio package and runtime.
  mlx-audio = final.callPackage ../packages/mlx-audio {};
  # WHY: pins MLX-LM for the configured Apple-Silicon model workflows.
  # REMOVE WHEN: nixpkgs provides a compatible MLX-LM package and runtime.
  mlx-lm = final.callPackage ../packages/mlx-lm {};
  # WHY: pins MLX-VLM for the configured Apple-Silicon model workflows.
  # REMOVE WHEN: nixpkgs provides a compatible MLX-VLM package and runtime.
  mlx-vlm = final.callPackage ../packages/mlx-vlm {};
  # WHY: supplies the Metal-enabled MLX wheel used for Apple-Silicon acceleration.
  # REMOVE WHEN: nixpkgs provides an equivalent Metal-enabled MLX package.
  mlx-metal = final.callPackage ../packages/mlx-metal {};
  # WHY: pins MLX Embeddings for the configured Apple-Silicon model workflows.
  # REMOVE WHEN: nixpkgs provides a compatible MLX Embeddings package and runtime.
  mlx-embeddings = final.callPackage ../packages/mlx-embeddings {};
  # WHY: provides pinned Hugging Face model downloads consumed by local inference services.
  # REMOVE WHEN: no configured service uses these model fetchers or an upstream fetcher replaces them.
  mlx-models = final.callPackage ../packages/mlx-models {
    inherit (final) lib stdenvNoCC curl jq gnugrep gnused cacert;
  };

  # WHY: keeps Linux devenv on the version pinned by the project flake input.
  # REMOVE WHEN: the nixpkgs devenv package matches that input on every supported platform.
  devenv =
    if final.stdenv.hostPlatform.isDarwin
    then _prev.devenv
    else inputs.devenv.packages.${final.stdenv.hostPlatform.system}.devenv;

  # WHY: injects project MLX packages into Python so consumers resolve Metal-enabled wheels.
  # REMOVE WHEN: nixpkgs' Python package overrides supply the same MLX package set.
  python3 = _prev.python3.override {
    packageOverrides = _pySelf: _pySuper: {
      # WHY: maps the MLX runtime to the project-built Metal wheel.
      # REMOVE WHEN: nixpkgs provides an equivalent Metal-enabled MLX package.
      mlx = final.mlx-metal;
      # WHY: selects the project-pinned MLX-LM release for Python consumers.
      # REMOVE WHEN: nixpkgs' Python set provides a compatible MLX-LM release.
      mlx-lm = final.mlx-lm;
      # WHY: selects the project-pinned MLX-VLM release for Python consumers.
      # REMOVE WHEN: nixpkgs' Python set provides a compatible MLX-VLM release.
      mlx-vlm = final.mlx-vlm;
      # WHY: selects the project-pinned MLX Audio release for Python consumers.
      # REMOVE WHEN: nixpkgs' Python set provides a compatible MLX Audio release.
      mlx-audio = final.mlx-audio;
      # WHY: selects the project-pinned MLX Embeddings release for Python consumers.
      # REMOVE WHEN: nixpkgs' Python set provides a compatible MLX Embeddings release.
      mlx-embeddings = final.mlx-embeddings;
    };
    self = final.python3;
  };
  # WHY: makes pkgs.python3Packages resolve to the overridden Python package set.
  # REMOVE WHEN: nixpkgs reliably derives this alias from the overridden python3.
  python3Packages = final.python3.pkgs;

  # WHY: pins the Gemma 4 31B model used by configured local inference workflows.
  # REMOVE WHEN: those workflows stop using this model or use another declared model.
  gemma4-31B-4bit = final.mlx-models.fetchModel {
    name = "gemma4-31B-4bit";
    modelPath = "mlx-community/gemma-4-31b-it-4bit";
    outputHash = "sha256-CCj8JPBY+WugmwUyk27dUSEwvWnVKNnDPaupsWnrAgk=";
  };
  # WHY: pins the Gemma 4 e4B model used by configured local inference workflows.
  # REMOVE WHEN: those workflows stop using this model or use another declared model.
  gemma4-e4B-4bit = final.mlx-models.fetchModel {
    name = "gemma4-e4B-4bit";
    modelPath = "mlx-community/gemma-4-e4b-it-4bit";
    outputHash = "sha256-7xQPqimzrXlumA3aaI/sBux1wZlrxRKarPX2fxtKgW0=";
  };
  # WHY: pins the Qwen 3.8 27B 4-bit model used by configured local inference workflows.
  # REMOVE WHEN: those workflows stop using this model or use another declared model.
  qwen3_8-27B-4bit = final.mlx-models.fetchModel {
    name = "qwen3_8-27B-4bit";
    modelPath = "mlx-community/Qwen3.8-27B-4bit";
    outputHash = "sha256-1AZjlDLkca3d8SUM4ibKb8MjrUBsoboRiZvXdOsfhTg=";
  };
  # WHY: pins the Qwen 3.8 27B mxfp4 model used by configured local inference workflows.
  # REMOVE WHEN: those workflows stop using this model or use another declared model.
  qwen3_8-27B-mxfp4 = final.mlx-models.fetchModel {
    name = "qwen3_8-27B-mxfp4";
    modelPath = "mlx-community/Qwen3.8-27B-mxfp4";
    outputHash = "sha256-936KGFXn/RDapliSBvcNWMDAUdAj/Djg5HtqlyEOStc=";
  };

  # Package Override Registry
  # See ../docs/reference/package-overrides.md for full documentation

  # WHY: skips the upstream OpenLDAP test suite, which is not needed for these system builds.
  # REMOVE WHEN: the upstream suite is reliable in our Nix build environment and can run in CI.
  openldap = _prev.openldap.overrideAttrs (_: {
    doCheck = false;
  });

  # WHY: nixpkgs' 18.5.0 fails with npm cache ENOTCACHED; 18.4.4 builds cleanly.
  # REMOVE WHEN: the nixpkgs package builds without the npm cache failure or this app is retired.
  super-productivity = _prev.super-productivity.overrideAttrs (oldAttrs: {
    version = "18.4.4";
    src = _prev.fetchFromGitHub {
      owner = "johannesjo";
      repo = "super-productivity";
      tag = "v18.4.4";
      hash = "sha256-ham19X3/aq4NJGwFneGhth2PLtpvcqBW4a41LDHjgp0=";
      postFetch = ''
        find $out -name package-lock.json -exec ${_prev.lib.getExe _prev.npm-lockfile-fix} -r {} \;
      '';
    };
    npmDeps = oldAttrs.npmDeps.overrideAttrs (_: {
      version = "18.4.4";
      src = _prev.fetchFromGitHub {
        owner = "johannesjo";
        repo = "super-productivity";
        tag = "v18.4.4";
        hash = "sha256-ham19X3/aq4NJGwFneGhth2PLtpvcqBW4a41LDHjgp0=";
        postFetch = ''
          find $out -name package-lock.json -exec ${_prev.lib.getExe _prev.npm-lockfile-fix} -r {} \;
        '';
      };
      outputHash = "sha256-YKVG2x4ipquJIQGTD22S1VEpmjLhNQiEEbAU6OiZRYE=";
    });
  });

  # WHY: avoids running Vector's upstream test suite in system package builds.
  # REMOVE WHEN: the suite is reliable and the project wants it enforced by Nix builds.
  vector = _prev.vector.overrideAttrs (_oldAttrs: {
    doCheck = false;
  });
}
// (
  if inputs ? bifrost
  then {
    # WHY: patches the upstream UI build until its OSS fallback exports the referenced type.
    # REMOVE WHEN: upstream exports VKCreationPolicyResponse from the access-profile types.
    bifrost-ui = (inputs.bifrost.packages.${final.stdenv.hostPlatform.system}.bifrost-ui).overrideAttrs (oldAttrs: {
      npmDeps = final.fetchNpmDeps {
        inherit (oldAttrs) src sourceRoot;
        name = "${oldAttrs.pname or oldAttrs.name}-npm-deps";
        hash = "sha256-cOswnT4ZahWX66h9oiw4t3r5GZeOH/yjbnTCAsjVgnw=";
      };
      # Temporary compatibility patch for the latest upstream OSS fallback:
      # VKCreationPolicyResponse is referenced there but is no longer exported
      # by the OSS accessProfile types. Remove this when upstream fixes it.
      postPatch =
        (oldAttrs.postPatch or "")
        + ''
          substituteInPlace app/_fallbacks/enterprise/lib/store/apis/accessProfileApi.ts \
            --replace ', VKCreationPolicyResponse' ""
          printf '%s\n' \
            "" \
            "type VKCreationPolicyResponse = {" \
            "  governed?: boolean;" \
            "  profile_name?: string;" \
            "};" \
            >> app/_fallbacks/enterprise/lib/store/apis/accessProfileApi.ts
        '';
    });

    # WHY: regenerates stale vendored module metadata in the pinned Bifrost HTTP source.
    # REMOVE WHEN: upstream ships vendor/modules.txt matching its go.mod dependency graph.
    bifrost-http =
      (inputs.bifrost.packages.${final.stdenv.hostPlatform.system}.bifrost-http.override {
        bifrost-ui = final.bifrost-ui;
      }).overrideAttrs (prev: {
        vendorHash = "sha256-GGpV5tE66LudwzCQROu2WDVF/5NPXnDbJZKRAtbWF34=";
        postPatch =
          (prev.postPatch or "")
          + ''
            rm -rf transports/vendor
            if ! grep -q '^github.com/mattn/go-isatty v0.0.24/go.mod ' transports/go.sum; then
              printf '%s\n' \
                'github.com/mattn/go-isatty v0.0.24/go.mod h1:nMCL3Zebbrt45jsMDgnfIwz6ydEQApk5oEI3HqDio6A=' \
                >> transports/go.sum
            fi
          '';
      });
  }
  else {}
)
