# Tests for the local Temporal launchd service.
{pkgs, ...}: let
  inherit (pkgs) lib;
  stubs = import ./stubs.nix {inherit pkgs;};

  temporalDefaults =
    (lib.evalModules {
      modules = stubs.base ++ stubs.darwinService ++ [../modules/services/temporal/darwin.nix];
    }).config.myConfig.temporal;

  temporalEnabled =
    (lib.evalModules {
      modules =
        stubs.base
        ++ stubs.darwinService
        ++ [
          ../modules/services/temporal/darwin.nix
          {
            config.myConfig.users = [{name = "monkey";}];
            config.myConfig.temporal = {
              enable = true;
              namespaces = ["inference" "testing"];
            };
          }
        ];
    }).config;
in {
  temporalOptionsTest = pkgs.runCommand "test-temporal-options" {} ''
    echo "=== Testing Temporal service options ==="

    ${
      if !temporalDefaults.enable
      then ''echo "  enable default = false: OK"''
      else ''echo "  enable should default to false"; exit 1''
    }

    ${
      if temporalDefaults.port == 7233 && temporalDefaults.uiPort == 8233
      then ''echo "  default ports = 7233/8233: OK"''
      else ''echo "  default ports are incorrect"; exit 1''
    }

    ${
      let
        agent = temporalEnabled.launchd.user.agents.temporal;
      in
        if
          lib.hasInfix "--namespace inference" agent.script
          && lib.hasInfix "--namespace testing" agent.script
          && lib.hasInfix "--db-filename /Users/monkey/.local/share/temporal/temporal.sqlite" agent.script
          && agent.serviceConfig.RunAtLoad
          && agent.serviceConfig.KeepAlive
        then ''echo "  enabled launchd configuration: OK"''
        else ''echo "  enabled launchd configuration is incorrect"; exit 1''
    }

    touch $out
  '';
}
