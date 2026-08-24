# Vector log shipper option tests
# Validates option defaults, custom values, and generated config for
# modules/services/vector/darwin.nix. Vector tails local launchd service
# logs (following this repo's /tmp/<service>(.error).log convention) and
# ships them to Loki.
{pkgs, ...}: let
  inherit (pkgs) lib;
  stubs = import ./stubs.nix {inherit pkgs;};

  vectorDefaults =
    (lib.evalModules {
      modules = stubs.vector;
    }).config.myConfig.vector;

  vectorCustom =
    (lib.evalModules {
      modules =
        stubs.vector
        ++ [
          {
            config.myConfig.users = [{name = "monkey";}];
            config.myConfig.loki = {
              enable = true;
              port = 3101;
            };
            config.myConfig.vector = {
              enable = true;
            };
          }
        ];
    }).config;

  vectorEnabledScript = vectorCustom.launchd.daemons.vector.command;
in {
  vectorOptionsTest = pkgs.runCommand "test-vector-options" {} ''
    echo "=== Testing Vector Option Defaults ==="

    ${
      if !vectorDefaults.enable
      then ''echo "  enable default = false: OK"''
      else ''echo "  enable should default to false!"; exit 1''
    }

    ${
      if vectorDefaults.logGlobs == ["/tmp/*.log"]
      then ''echo "  logGlobs default = [ /tmp/*.log ]: OK"''
      else ''echo "  logGlobs should default to [ /tmp/*.log ]!"; exit 1''
    }

    echo "All Vector option defaults verified"
    touch $out
  '';

  vectorCustomOptionsTest = pkgs.runCommand "test-vector-custom-options" {} ''
    echo "=== Testing Vector Custom Options ==="

    ${
      if vectorCustom.myConfig.vector.enable
      then ''echo "  enable = true: OK"''
      else ''echo "  enable should be true!"; exit 1''
    }

    echo "All Vector custom options verified"
    touch $out
  '';

  # Verify the generated Vector config ships logs to the configured Loki
  # endpoint (host + port derived from myConfig.loki, not hardcoded).
  vectorGeneratedConfigTest = pkgs.runCommand "test-vector-generated-config" {} ''
    echo "=== Testing Vector Generated Config ==="

    SCRIPT=${vectorEnabledScript}
    CONFIG=$(grep -o -- '--config /nix/store/[^ ]*' "$SCRIPT" | head -1 | cut -d' ' -f2)

    if grep -q '"endpoint":"http://127.0.0.1:3101"' "$CONFIG"; then
      echo "  loki sink endpoint derived from myConfig.loki.port (3101): OK"
    else
      echo "  FAIL: loki sink endpoint should be http://127.0.0.1:3101"; exit 1
    fi

    if grep -q '"include":\["/tmp/\*.log"\]' "$CONFIG"; then
      echo "  file source globs /tmp/*.log service logs: OK"
    else
      echo "  FAIL: file source should glob /tmp/*.log"; exit 1
    fi

    echo "All Vector generated config tests passed"
    touch $out
  '';
}
