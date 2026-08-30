# Bifrost AI gateway option tests
# Validates option defaults, custom values, and generated provider config
{pkgs, ...}: let
  inherit (pkgs) lib;
  stubs = import ./stubs.nix {inherit pkgs;};

  bifrostDefaults =
    (lib.evalModules {
      modules = stubs.bifrost;
    }).config.myConfig.bifrost;

  bifrostCustom =
    (lib.evalModules {
      modules =
        stubs.bifrost
        ++ [
          {
            config.myConfig.bifrost = {
              enable = true;
              port = 9090;
              host = "127.0.0.1";
              logLevel = "debug";
              appDir = "/var/lib/bifrost";
              upstreams = {
                "omlx" = {
                  url = "http://localhost:8300/v1";
                  type = "openai";
                  apiKey = "dummy";
                  allowPrivateNetwork = true;
                  requestTimeout = 60;
                  maxRetries = 4;
                  retryBackoffInitialMs = 250;
                  retryBackoffMaxMs = 8000;
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
      if bifrostCustom.upstreams ? "omlx"
      then ''echo "  upstreams.omlx defined: OK"''
      else ''echo "  upstreams.omlx should be defined!"; exit 1''
    }

    ${
      if bifrostCustom.upstreams.omlx.url == "http://localhost:8300/v1"
      then ''echo "  upstream URL correct: OK"''
      else ''echo "  upstream URL should be http://localhost:8300/v1!"; exit 1''
    }

    ${
      if bifrostCustom.upstreams.omlx.type == "openai"
      then ''echo "  upstream type = openai: OK"''
      else ''echo "  upstream type should be openai!"; exit 1''
    }

    ${
      if builtins.elem "qwen3.5" bifrostCustom.upstreams.omlx.models
      then ''echo "  upstream models contains qwen3.5: OK"''
      else ''echo "  upstream models should contain qwen3.5!"; exit 1''
    }

    ${
      if bifrostCustom.upstreams.omlx.maxRetries == 4
      then ''echo "  upstream maxRetries = 4: OK"''
      else ''echo "  upstream maxRetries should be 4!"; exit 1''
    }

    ${
      if bifrostCustom.upstreams.omlx.retryBackoffInitialMs == 250
      then ''echo "  upstream retryBackoffInitialMs = 250: OK"''
      else ''echo "  upstream retryBackoffInitialMs should be 250!"; exit 1''
    }

    ${
      if bifrostCustom.upstreams.omlx.retryBackoffMaxMs == 8000
      then ''echo "  upstream retryBackoffMaxMs = 8000: OK"''
      else ''echo "  upstream retryBackoffMaxMs should be 8000!"; exit 1''
    }

    echo "All Bifrost custom options verified"
    touch $out
  '';

  # Verify the generated provider config (embedded in the launchd script)
  # carries retry settings into network_config. Bifrost's upstream default is
  # max_retries = 0 — one attempt, no retries — which is what let transient
  # 503s from a busy local engine fail whole agent turns.
  bifrostRetryConfigTest = let
    retryEval =
      (lib.evalModules {
        modules =
          stubs.bifrost
          ++ [
            {
              config.myConfig.users = [{name = "monkey";}];
              config.myConfig.bifrost = {
                enable = true;
                upstreams."local" = {
                  url = "http://localhost:8300";
                  type = "openai";
                  maxRetries = 3;
                  retryBackoffInitialMs = 250;
                  retryBackoffMaxMs = 4000;
                };
                upstreams."local-defaults" = {
                  url = "http://localhost:8301";
                  type = "openai";
                };
              };
            }
          ];
      })
      .config;
  in
    pkgs.runCommand "test-bifrost-retry-config" {} ''
      echo "=== Testing Bifrost Generated Retry Config ==="
      SCRIPT=${retryEval.launchd.daemons.bifrost.command}

      if grep -q '"max_retries":3' "$SCRIPT"; then
        echo "  max_retries = 3 in generated config: OK"
      else
        echo "  FAIL: generated config should contain \"max_retries\":3"; exit 1
      fi

      if grep -q '"retry_backoff_initial":"250ms"' "$SCRIPT"; then
        echo "  retry_backoff_initial = 250ms: OK"
      else
        echo "  FAIL: generated config should contain \"retry_backoff_initial\":\"250ms\""; exit 1
      fi

      if grep -q '"retry_backoff_max":"4000ms"' "$SCRIPT"; then
        echo "  retry_backoff_max = 4000ms: OK"
      else
        echo "  FAIL: generated config should contain \"retry_backoff_max\":\"4000ms\""; exit 1
      fi

      # Upstreams that don't opt in stay at Bifrost's stock defaults
      if grep -q '"max_retries":0' "$SCRIPT"; then
        echo "  default max_retries = 0 (upstream default preserved): OK"
      else
        echo "  FAIL: unconfigured upstream should keep max_retries = 0"; exit 1
      fi

      if grep -q '"retry_backoff_initial":"500ms"' "$SCRIPT" && grep -q '"retry_backoff_max":"5000ms"' "$SCRIPT"; then
        echo "  default backoffs = 500ms/5000ms (upstream defaults): OK"
      else
        echo "  FAIL: unconfigured upstream should keep upstream backoff defaults"; exit 1
      fi

      echo "All Bifrost retry config tests passed"
      touch $out
    '';
}
