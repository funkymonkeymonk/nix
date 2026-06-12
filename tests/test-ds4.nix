# ds4 LLM inference server option tests
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

  ds4Defaults =
    (lib.evalModules {
      modules = stubModules;
    }).config.myConfig.ds4;

  ds4Custom =
    (lib.evalModules {
      modules =
        stubModules
        ++ [
          {
            config.myConfig.ds4 = {
              enable = true;
              server = {
                host = "127.0.0.1";
                port = 9100;
                contextSize = 65536;
                kvDiskSpaceMb = 16384;
                cors = true;
                power = 70;
              };
              model = {
                name = "ds4-test";
                path = "/path/to/model.gguf";
                gguf = "model.gguf";
              };
            };
          }
        ];
    }).config.myConfig.ds4;
in {
  ds4OptionsTest =
    pkgs.runCommand "test-ds4-options"
    {}
    ''
      echo "=== Testing ds4 Option Defaults ==="

      ${
        if !ds4Defaults.enable
        then ''echo "  enable default = false: OK"''
        else ''echo "  enable should default to false!"; exit 1''
      }

      ${
        if ds4Defaults.server.host == "0.0.0.0"
        then ''echo "  server.host default = 0.0.0.0: OK"''
        else ''echo "  server.host should default to 0.0.0.0!"; exit 1''
      }

      ${
        if ds4Defaults.server.port == 8100
        then ''echo "  server.port default = 8100: OK"''
        else ''echo "  server.port should default to 8100!"; exit 1''
      }

      ${
        if ds4Defaults.server.contextSize == 32768
        then ''echo "  server.contextSize default = 32768: OK"''
        else ''echo "  server.contextSize should default to 32768!"; exit 1''
      }

      ${
        if ds4Defaults.server.kvDiskSpaceMb == 8192
        then ''echo "  server.kvDiskSpaceMb default = 8192: OK"''
        else ''echo "  server.kvDiskSpaceMb should default to 8192!"; exit 1''
      }

      ${
        if ds4Defaults.server.cors == false
        then ''echo "  server.cors default = false: OK"''
        else ''echo "  server.cors should default to false!"; exit 1''
      }

      ${
        if ds4Defaults.server.power == null
        then ''echo "  server.power default = null: OK"''
        else ''echo "  server.power should default to null!"; exit 1''
      }

      ${
        if ds4Defaults.model.name == "deepseek-v4-flash"
        then ''echo "  model.name default = deepseek-v4-flash: OK"''
        else ''echo "  model.name should default to deepseek-v4-flash!"; exit 1''
      }

      echo ""
      echo "=== Testing ds4 Custom Options ==="

      ${
        if ds4Custom.server.host == "127.0.0.1"
        then ''echo "  server.host = 127.0.0.1: OK"''
        else ''echo "  server.host should be 127.0.0.1!"; exit 1''
      }

      ${
        if ds4Custom.server.port == 9100
        then ''echo "  server.port = 9100: OK"''
        else ''echo "  server.port should be 9100!"; exit 1''
      }

      ${
        if ds4Custom.server.contextSize == 65536
        then ''echo "  server.contextSize = 65536: OK"''
        else ''echo "  server.contextSize should be 65536!"; exit 1''
      }

      ${
        if ds4Custom.model.name == "ds4-test"
        then ''echo "  model.name = ds4-test: OK"''
        else ''echo "  model.name should be ds4-test!"; exit 1''
      }

      echo ""
      echo "All ds4 option tests passed"
      touch $out
    '';
}
