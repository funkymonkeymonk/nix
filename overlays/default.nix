# Custom package overlays
{inputs ? {}}: final: _prev:
{
  rtk = final.callPackage ../packages/rtk {};
  yaks = final.callPackage ../packages/yaks {};
  lume = final.callPackage ../packages/lume {};
  vane = final.callPackage ../packages/vane {};
  ds4 = final.callPackage ../packages/ds4 {};

  mlx-models = final.callPackage ../packages/mlx-models {
    inherit (final) lib stdenvNoCC curl jq gnugrep gnused cacert;
  };

  gemma4-31B-OptiQ-4bit = final.mlx-models.fetchModel {
    name = "gemma4-31B-OptiQ-4bit";
    modelPath = "mlx-community/gemma-4-31B-it-OptiQ-4bit";
    outputHash = "sha256-adiGBvHq9gCDPiHaFCp7xwX4A9OY/nLZw3jGS0kkvQk=";
  };
  gemma4-12B-OptiQ-4bit = final.mlx-models.fetchModel {
    name = "gemma4-12B-OptiQ-4bit";
    modelPath = "mlx-community/gemma-4-12B-it-OptiQ-4bit";
    outputHash = final.lib.fakeHash;
  };
  qwen-embed = final.mlx-models.fetchModel {
    name = "qwen-embed";
    modelPath = "mlx-community/Qwen3-Embedding-4B-4bit-DWQ";
    outputHash = final.lib.fakeHash;
  };
  deepseek-v4-flash-q2 = final.mlx-models.fetchGgufModel {
    name = "deepseek-v4-flash-q2";
    modelPath = "antirez/deepseek-v4-gguf";
    outputHash = final.lib.fakeHash;
  };

  # Package Override Registry
  # See ../docs/reference/package-overrides.md for full documentation
  #
  # opencode 1.2.15 - Avoids edit/write hanging bug (Issue #20477)
  # Bug report: https://github.com/anomalyco/opencode/issues/20477
  # Status: Still open as of 2026-05-10 (affects v1.14.35 in nixpkgs)
  # Test to unlock: Run `opencode edit <large-file>` on macOS, verify no "Preparing write..." hang
  # Note: Uses fetchgit instead of fetchFromGitHub for hash stability
  opencode = _prev.opencode.overrideAttrs (oldAttrs: rec {
    version = "1.2.15";
    src = _prev.fetchgit {
      url = "https://github.com/anomalyco/opencode.git";
      rev = "refs/tags/v${version}";
      hash = "sha256-26MV9TbyAF0KFqZtIHPYu6wqJwf0pNPdW/D3gDQEUlQ=";
    };
    node_modules = oldAttrs.node_modules.overrideAttrs {
      outputHash = "sha256-71id1sB2dQ8Egj8zGFjcEIeOmU/t9HRoRwPHb9fWtC8=";
    };
  });

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
      }).overrideAttrs (prev: {
        vendorHash = "sha256-tnyDAoXcshsrWmaJ8NXL7XCT4795G+oi5ReOfh1fXzw=";
      });
  }
  else {}
)
