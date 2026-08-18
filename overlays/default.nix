# Custom package overlays
{inputs ? {}}: final: _prev:
{
  rtk = final.callPackage ../packages/rtk {};
  yaks = final.callPackage ../packages/yaks {};
  jj-hooks = final.callPackage ../packages/jj-hooks {};
  lume = final.callPackage ../packages/lume {};
  vane = final.callPackage ../packages/vane {};
  lm-eval = final.callPackage ../packages/benchmarks/lm-eval {};
  lighteval = final.callPackage ../packages/benchmarks/lighteval {};
  mlx-audio = final.callPackage ../packages/mlx-audio {};
  mlx-lm = final.callPackage ../packages/mlx-lm {};
  mlx-vlm = final.callPackage ../packages/mlx-vlm {};
  mlx-metal = final.callPackage ../packages/mlx-metal {};
  vllm-mlx = final.callPackage ../packages/vllm-mlx {};
  mlx-embeddings = final.callPackage ../packages/mlx-embeddings {};
  mlx-models = final.callPackage ../packages/mlx-models {
    inherit (final) lib stdenvNoCC curl jq gnugrep gnused cacert;
  };

  # Override python3Packages so vllm-mlx dependencies resolve correctly.
  # Use mlx-metal (prebuilt wheels with GPU support) instead of nixpkgs mlx
  # which builds without Metal acceleration.
  python3 = _prev.python3.override {
    packageOverrides = _pySelf: _pySuper: {
      mlx = final.mlx-metal;
      mlx-lm = final.mlx-lm;
      mlx-vlm = final.mlx-vlm;
      mlx-audio = final.mlx-audio;
      mlx-embeddings = final.mlx-embeddings;
    };
    self = final.python3;
  };
  python3Packages = final.python3.pkgs;

  gemma4-31B-4bit = final.mlx-models.fetchModel {
    name = "gemma4-31B-4bit";
    modelPath = "mlx-community/gemma-4-31b-it-4bit";
    outputHash = "sha256-CCj8JPBY+WugmwUyk27dUSEwvWnVKNnDPaupsWnrAgk=";
  };
  gemma4-e4B-4bit = final.mlx-models.fetchModel {
    name = "gemma4-e4B-4bit";
    modelPath = "mlx-community/gemma-4-e4b-it-4bit";
    outputHash = "sha256-7xQPqimzrXlumA3aaI/sBux1wZlrxRKarPX2fxtKgW0=";
  };
  qwen3_8-27B-8bit = final.mlx-models.fetchModel {
    name = "qwen3_8-27B-8bit";
    modelPath = "mlx-community/Qwen3.8-27B-8bit";
    outputHash = "sha256-zTs3ZI27cVeHV35bhDCKMiK2MCDlE1iW6gMQ39i1Nws=";
  };
  qwen3_8-27B-4bit = final.mlx-models.fetchModel {
    name = "qwen3_8-27B-4bit";
    modelPath = "mlx-community/Qwen3.8-27B-4bit";
    outputHash = "sha256-1AZjlDLkca3d8SUM4ibKb8MjrUBsoboRiZvXdOsfhTg=";
  };
  qwen3_8-27B-MTP-8bit = final.mlx-models.fetchModel {
    name = "qwen3_8-27B-MTP-8bit";
    modelPath = "mlx-community/Qwen3.8-27B-MTP-8bit";
    outputHash = "sha256-hyCLI6p7Tc44pC3LigDY2dXarcCUx/lmB7AvtsPHLWY=";
  };
  qwen3_8-27B-MTP-4bit = final.mlx-models.fetchModel {
    name = "qwen3_8-27B-MTP-4bit";
    modelPath = "mlx-community/Qwen3.8-27B-MTP-4bit";
    outputHash = "sha256-i+g9zo8XyR9fbD7EEHRu2Zd5s+ZBEayn+TJdgnU581Q=";
  };
  # Package Override Registry
  # See ../docs/reference/package-overrides.md for full documentation

  openldap = _prev.openldap.overrideAttrs (_: {
    doCheck = false;
  });

  # super-productivity 18.5.0 fails to build (npm cache ENOTCACHED error)
  # Pinned to 18.4.4 which builds cleanly. Revisit when nixpkgs updates.
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
}
// (
  if inputs ? bifrost
  then {
    bifrost-ui = (inputs.bifrost.packages.${final.system}.bifrost-ui).overrideAttrs (oldAttrs: {
      npmDeps = final.fetchNpmDeps {
        inherit (oldAttrs) src sourceRoot;
        name = "${oldAttrs.pname or oldAttrs.name}-npm-deps";
        hash = "sha256-1eEw976l9xb0nLyoc5vUv1536EUvmdVtCBdz+FpprgQ=";
      };
    });

    bifrost-http =
      ((inputs.bifrost.packages.${final.system}.bifrost-http).override {
        bifrost-ui = final.bifrost-ui;
      }).overrideAttrs (_prev: {
        vendorHash = "sha256-iQp50tyrS6w5YBU1dvOB3R3DbeAdFBXJobdhvM7x5bo=";
      });
  }
  else {}
)
