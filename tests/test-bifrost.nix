# Bifrost AI gateway option tests
# Validates option defaults and custom values
{pkgs, ...}: let
  inherit (pkgs) lib;

  stubModules = [
    ../modules/common/options.nix
    {
      options.nixpkgs.hostPlatform = lib.mkOption {
        type = lib.types.anything;
        default = {inherit (pkgs.stdenv.hostPlatform) system;};
      };
    }
    {
      config._module.args = {inherit pkgs;};
    }
  ];

  bifrostDefaults =
    (lib.evalModules {
      modules = stubModules;
    }).config.myConfig.bifrost;

  bifrostCustom =
    (lib.evalModules {
      modules =
        stubModules
        ++ [
          {
            config.myConfig.bifrost = {
              enable = true;
              port = 9090;
              host = "127.0.0.1";
              logLevel = "debug";
              appDir = "/var/lib/bifrost";
              upstreams = {
                "vllm-mlx-local" = {
                  url = "http://localhost:8300/v1";
                  type = "vllm";
                  apiKey = "dummy";
                  allowPrivateNetwork = true;
                  requestTimeout = 60;
                  models = ["qwen3.5"];
                };
              };
            };
          }
        ];
    }).config.myConfig.bifrost;
in {
  bifrostOptionsTest = pkgs.runCommand "test-bifrost-options" {} ''
    echo "=== Testing Bifrost Option Defaults ==="

    ${
      if !bifrostDefaults.enable
      then ''echo "  enable default = false: OK"''
      else ''echo "  enable should default to false!"; exit 1''
    }

    ${
      if bifrostDefaults.port == 8081
      then ''echo "  port default = 8081: OK"''
      else ''echo "  port should default to 8081!"; exit 1''
    }

    ${
      if bifrostDefaults.host == "0.0.0.0"
      then ''echo "  host default = 0.0.0.0: OK"''
      else ''echo "  host should default to 0.0.0.0!"; exit 1''
    }

    ${
      if bifrostDefaults.logLevel == "info"
      then ''echo "  logLevel default = info: OK"''
      else ''echo "  logLevel should default to info!"; exit 1''
    }

    ${
      if bifrostDefaults.appDir == "$HOME/.config/bifrost"
      then ''echo "  appDir default = \$HOME/.config/bifrost: OK"''
      else ''echo "  appDir should default to \$HOME/.config/bifrost!"; exit 1''
    }

    ${
      if bifrostDefaults.upstreams == {}
      then ''echo "  upstreams default = {}: OK"''
      else ''echo "  upstreams should default to {}!"; exit 1''
    }

    echo "All Bifrost option defaults verified"
    touch $out
  '';

  bifrostCustomOptionsTest = pkgs.runCommand "test-bifrost-custom-options" {} ''
    echo "=== Testing Bifrost Custom Options ==="

    ${
      if bifrostCustom.enable
      then ''echo "  enable = true: OK"''
      else ''echo "  enable should be true!"; exit 1''
    }

    ${
      if bifrostCustom.port == 9090
      then ''echo "  port = 9090: OK"''
      else ''echo "  port should be 9090!"; exit 1''
    }

    ${
      if bifrostCustom.host == "127.0.0.1"
      then ''echo "  host = 127.0.0.1: OK"''
      else ''echo "  host should be 127.0.0.1!"; exit 1''
    }

    ${
      if bifrostCustom.logLevel == "debug"
      then ''echo "  logLevel = debug: OK"''
      else ''echo "  logLevel should be debug!"; exit 1''
    }

    ${
      if bifrostCustom.appDir == "/var/lib/bifrost"
      then ''echo "  appDir = /var/lib/bifrost: OK"''
      else ''echo "  appDir should be /var/lib/bifrost!"; exit 1''
    }

    ${
      if bifrostCustom.upstreams ? "vllm-mlx-local"
      then ''echo "  upstreams.vllm-mlx-local defined: OK"''
      else ''echo "  upstreams.vllm-mlx-local should be defined!"; exit 1''
    }

    ${
      if bifrostCustom.upstreams."vllm-mlx-local".url == "http://localhost:8300/v1"
      then ''echo "  upstream URL correct: OK"''
      else ''echo "  upstream URL should be http://localhost:8300/v1!"; exit 1''
    }

    ${
      if bifrostCustom.upstreams."vllm-mlx-local".type == "vllm"
      then ''echo "  upstream type = vllm: OK"''
      else ''echo "  upstream type should be vllm!"; exit 1''
    }

    ${
      if builtins.elem "qwen3.5" bifrostCustom.upstreams."vllm-mlx-local".models
      then ''echo "  upstream models contains qwen3.5: OK"''
      else ''echo "  upstream models should contain qwen3.5!"; exit 1''
    }

    echo "All Bifrost custom options verified"
    touch $out
  '';
}
