# Bifrost AI gateway option tests
# Validates option defaults, custom values, and generated provider config
{pkgs, ...}: let
  inherit (pkgs) lib;
  stubs = import ./stubs.nix {inherit pkgs;};

  bifrostDefaults =
    (lib.evalModules {
      modules = stubs.bifrost;
    }).config.myConfig.bifrost;

  bifrostWithoutTailscaleEval = lib.evalModules {
    modules =
      stubs.bifrost
      ++ [
        {
          config.myConfig.users = [{name = "monkey";}];
          config.myConfig.bifrost = {
            enable = true;
            host = "127.0.0.1";
            port = 8081;
          };
        }
      ];
  };
  bifrostWithoutTailscale = bifrostWithoutTailscaleEval.config;
  bifrostStandaloneDaemon = bifrostWithoutTailscale.launchd.daemons.bifrost or {};
  bifrostOptions = bifrostWithoutTailscaleEval.options.myConfig.bifrost or {};

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
  bifrostOpenCodeGoEval = lib.evalModules {
    modules =
      stubs.bifrost
      ++ [
        {
          config.myConfig.users = [{name = "monkey";}];
          config.myConfig.bifrost = {
            enable = true;
            modelMetadata."omlx/qwen3.8-27b" = {
              contextLength = 128000;
              maxOutputTokens = 30720;
            };
            upstreams."opencode-go" = {
              type = "opencode-go";
              url = "https://opencode.ai/zen/go";
              apiKey = "FIXTURE_SECRET_SHOULD_NOT_LEAK";
              apiKeyFile = ".pi/agent/secrets/opencode-go-apikey";
            };
          };
        }
      ];
  };
  bifrostOpenCodeGo = bifrostOpenCodeGoEval.config;
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

  bifrostTailscaleServeTest = pkgs.runCommand "test-bifrost-tailscale-serve" {} ''
    echo "=== Testing Tailscale Serve ownership ==="
    BIFROST_SCRIPT=${bifrostStandaloneDaemon.command or ""}
    ${pkgs.bash}/bin/bash -n "$BIFROST_SCRIPT"
    if ${lib.boolToString (!(builtins.hasAttr "bifrost-tailscale-serve" bifrostWithoutTailscale.launchd.daemons))}; then
      echo "Bifrost no longer owns a Tailscale Serve daemon: OK"
    else
      echo "FAIL: Tailscale Serve must be configured centrally, not by Bifrost"; exit 1
    fi
    if ${lib.boolToString (!(builtins.hasAttr "exposeViaTailscaleServe" bifrostOptions) && !(builtins.hasAttr "tailscaleServePort" bifrostOptions))}; then
      echo "Bifrost has no Tailscale-owned options: OK"
    else
      echo "FAIL: Tailscale Serve options must be moved out of Bifrost"; exit 1
    fi
    if ! grep -qi 'tailscale' "$BIFROST_SCRIPT"; then
      echo "Bifrost launcher contains no Tailscale CLI setup: OK"
    else
      echo "FAIL: Bifrost launcher must not configure Tailscale"; exit 1
    fi
    touch $out
  '';

  bifrostAnthropicConfigTest = let
    anthropicEval =
      (lib.evalModules {
        modules =
          stubs.bifrost
          ++ [
            {
              config.myConfig.bifrost = {
                enable = true;
                upstreams.omlx = {
                  url = "http://localhost:8300";
                  type = "anthropic";
                };
              };
            }
          ];
      })
      .config;
  in
    pkgs.runCommand "test-bifrost-anthropic-config" {} ''
      echo "=== Testing Bifrost Anthropic Provider Config ==="
      SCRIPT=${anthropicEval.launchd.daemons.bifrost.command}

      if grep -q '"base_provider_type":"anthropic"' "$SCRIPT"; then
        echo "  custom provider base type = anthropic: OK"
      else
        echo "  custom provider base type should be anthropic!"; exit 1
      fi

      if grep -q '"responses":true' "$SCRIPT" && grep -q '"responses_stream":true' "$SCRIPT"; then
        echo "  Anthropic responses routes enabled: OK"
      else
        echo "  Anthropic responses routes should be enabled!"; exit 1
      fi
      touch $out
    '';

  # Confirm overlay package metadata matches the pinned upstream transport.
  bifrostPackageVersionTest = pkgs.runCommand "test-bifrost-package-version" {} ''
    test "${pkgs.bifrost-http.version}" = "2.5.1"
    touch $out
  '';

  bifrostOpenCodeGoTest = pkgs.runCommand "test-bifrost-opencode-go" {} ''
    echo "=== Testing Bifrost OpenCode Go and model metadata ==="
    SCRIPT=${bifrostOpenCodeGo.launchd.daemons.bifrost.command}
    METADATA=${bifrostOpenCodeGo.launchd.daemons.bifrost.serviceConfig.EnvironmentVariables.BIFROST_MODEL_METADATA_FILE}

    ${pkgs.python3}/bin/python - "$SCRIPT" <<'PY'
    import json
    import shlex
    import sys

    script = open(sys.argv[1], encoding="utf-8").read()
    config_line = next(line for line in script.splitlines() if line.startswith("printf '%s\\n' "))
    config = json.loads(shlex.split(config_line)[2])
    provider = config["providers"]["opencode-go"]
    assert "custom_provider_config" not in provider, provider
    assert provider["keys"][0]["value"] == "env.BIFROST_OPENCODE_GO_API_KEY", provider
    assert provider["network_config"]["base_url"] == "https://opencode.ai/zen/go", provider
    assert "FIXTURE_SECRET_SHOULD_NOT_LEAK" not in script
    assert ".pi/agent/secrets/opencode-go-apikey" in script
    PY

    ${pkgs.jq}/bin/jq -e '
      .["omlx/qwen3.8-27b"].context_length == 128000 and
      .["omlx/qwen3.8-27b"].max_output_tokens == 30720
    ' "$METADATA" >/dev/null

    echo "Bifrost Go provider uses the existing secret file without exposing its value: OK"
    echo "Bifrost local Qwen metadata is advertised through its metadata file: OK"
    touch $out
  '';

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
