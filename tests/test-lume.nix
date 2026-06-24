# Lume option tests
# Validates option defaults and custom values from modules/services/lume/darwin.nix
{pkgs, ...}: let
  inherit (pkgs) lib;

  lumeStubs = [
    ../modules/services/lume/darwin.nix
    {
      options.nixpkgs.hostPlatform = lib.mkOption {
        type = lib.types.anything;
        default = {inherit (pkgs.stdenv.hostPlatform) system;};
      };
      options.myConfig.users = lib.mkOption {
        type = lib.types.listOf lib.types.anything;
        default = [];
      };
      options.myConfig.isDarwin = lib.mkOption {
        type = lib.types.bool;
        default = true;
      };
      options.environment.systemPackages = lib.mkOption {
        type = lib.types.listOf lib.types.package;
        default = [];
      };
      options.launchd.daemons = lib.mkOption {
        type = lib.types.attrsOf lib.types.anything;
        default = {};
      };
      options.system.activationScripts = lib.mkOption {
        type = lib.types.attrsOf lib.types.anything;
        default = {};
      };
    }
    {
      config._module.args = {inherit pkgs;};
    }
  ];

  lumeDefaults =
    (lib.evalModules {
      modules = lumeStubs;
    }).config.myConfig.lume;

  lumeCustom =
    (lib.evalModules {
      modules =
        lumeStubs
        ++ [
          {
            config.myConfig.lume = {
              enable = true;
              port = 8888;
              enableBackgroundService = false;
              enableAutoUpdater = false;
              prePullImages = ["macos-tahoe-vanilla:latest"];
            };
          }
        ];
    }).config.myConfig.lume;
in {
  lumeOptionsTest = pkgs.runCommand "test-lume-options" {} ''
    echo "=== Testing Lume Option Defaults ==="

    ${
      if !lumeDefaults.enable
      then ''echo "  enable default = false: OK"''
      else ''echo "  enable should default to false!"; exit 1''
    }

    ${
      if lumeDefaults.port == 7777
      then ''echo "  port default = 7777: OK"''
      else ''echo "  port should default to 7777!"; exit 1''
    }

    ${
      if lumeDefaults.enableBackgroundService
      then ''echo "  enableBackgroundService default = true: OK"''
      else ''echo "  enableBackgroundService should default to true!"; exit 1''
    }

    ${
      if lumeDefaults.enableAutoUpdater
      then ''echo "  enableAutoUpdater default = true: OK"''
      else ''echo "  enableAutoUpdater should default to true!"; exit 1''
    }

    ${
      if lumeDefaults.prePullImages == []
      then ''echo "  prePullImages default = []: OK"''
      else ''echo "  prePullImages should default to []!"; exit 1''
    }

    echo "All Lume option defaults verified"
    touch $out
  '';

  lumeCustomOptionsTest = pkgs.runCommand "test-lume-custom-options" {} ''
    echo "=== Testing Lume Custom Options ==="

    ${
      if lumeCustom.enable
      then ''echo "  enable = true: OK"''
      else ''echo "  enable should be true!"; exit 1''
    }

    ${
      if lumeCustom.port == 8888
      then ''echo "  port = 8888: OK"''
      else ''echo "  port should be 8888!"; exit 1''
    }

    ${
      if !lumeCustom.enableBackgroundService
      then ''echo "  enableBackgroundService = false: OK"''
      else ''echo "  enableBackgroundService should be false!"; exit 1''
    }

    ${
      if !lumeCustom.enableAutoUpdater
      then ''echo "  enableAutoUpdater = false: OK"''
      else ''echo "  enableAutoUpdater should be false!"; exit 1''
    }

    ${
      if builtins.elem "macos-tahoe-vanilla:latest" lumeCustom.prePullImages
      then ''echo "  prePullImages contains macos-tahoe-vanilla:latest: OK"''
      else ''echo "  prePullImages should contain macos-tahoe-vanilla:latest!"; exit 1''
    }

    echo "All Lume custom options verified"
    touch $out
  '';
}
