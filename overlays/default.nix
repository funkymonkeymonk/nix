# Custom package overlays
{inputs ? {}}: final: _prev:
{
  rtk = final.callPackage ../packages/rtk {};
  yaks = final.callPackage ../packages/yaks {};
  lume = final.callPackage ../packages/lume {};
  vane = final.callPackage ../packages/vane {};
  mlx-audio = final.callPackage ../packages/mlx-audio {};
  mlx-lm = final.callPackage ../packages/mlx-lm {};
  mlx-vlm = final.callPackage ../packages/mlx-vlm {};
  vllm-mlx = final.callPackage ../packages/vllm-mlx {};
  mlx-embeddings = final.callPackage ../packages/mlx-embeddings {};
  mlx-models = final.callPackage ../packages/mlx-models {
    inherit (final) lib stdenvNoCC curl jq gnugrep gnused cacert;
  };

  # Override python3Packages so vllm-mlx dependencies resolve correctly
  python3 = _prev.python3.override {
    packageOverrides = pySelf: pySuper: {
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
    bifrost-http =
      ((inputs.bifrost.packages.${final.system}.bifrost-http).override {
        bifrost-ui = final.runCommand "bifrost-ui-dummy" {} "mkdir $out";
      }).overrideAttrs (_prev: {
        vendorHash = "sha256-apPaRE3ZOaXrETX5EbhvPsgKdQa8IXoe4epeudytOUI=";
      });
  }
  else {}
)
