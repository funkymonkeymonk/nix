# vMLX LLM inference server option tests
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

  vmlxDefaults =
    (lib.evalModules {
      modules = stubModules;
    }).config.myConfig.vmlx;

  vmlxCustom =
    (lib.evalModules {
      modules =
        stubModules
        ++ [
          {
            config.myConfig.vmlx = {
              enable = true;
              server = {
                host = "127.0.0.1";
                port = 9300;
              };
              kvCacheQuantization = "q4";
              enableDiskCache = false;
              enableJIT = true;
              maxPromptTokens = 65536;
              model = {
                name = "test-model";
                path = "mlx-community/test-model-4bit";
              };
            };
          }
        ];
    }).config.myConfig.vmlx;
in {
  vmlxOptionsTest =
    pkgs.runCommand "test-vmlx-options"
    {}
    ''
      echo "=== Testing vMLX Option Defaults ==="

      ${
        if !vmlxDefaults.enable
        then ''echo "  enable default = false: OK"''
        else ''echo "  enable should default to false!"; exit 1''
      }

      ${
        if vmlxDefaults.server.host == "0.0.0.0"
        then ''echo "  server.host default = 0.0.0.0: OK"''
        else ''echo "  server.host should default to 0.0.0.0!"; exit 1''
      }

      ${
        if vmlxDefaults.server.port == 8300
        then ''echo "  server.port default = 8300: OK"''
        else ''echo "  server.port should default to 8300!"; exit 1''
      }

      ${
        if vmlxDefaults.kvCacheQuantization == "q8"
        then ''echo "  kvCacheQuantization default = q8: OK"''
        else ''echo "  kvCacheQuantization should default to q8!"; exit 1''
      }

      ${
        if vmlxDefaults.maxPromptTokens == 32768
        then ''echo "  maxPromptTokens default = 32768: OK"''
        else ''echo "  maxPromptTokens should default to 32768!"; exit 1''
      }

      echo ""
      echo "=== Testing vMLX Custom Options ==="

      ${
        if vmlxCustom.enable == true
        then ''echo "  enable = true: OK"''
        else ''echo "  enable should be true!"; exit 1''
      }

      ${
        if vmlxCustom.server.host == "127.0.0.1"
        then ''echo "  server.host = 127.0.0.1: OK"''
        else ''echo "  server.host should be 127.0.0.1!"; exit 1''
      }

      ${
        if vmlxCustom.server.port == 9300
        then ''echo "  server.port = 9300: OK"''
        else ''echo "  server.port should be 9300!"; exit 1''
      }

      ${
        if vmlxCustom.kvCacheQuantization == "q4"
        then ''echo "  kvCacheQuantization = q4: OK"''
        else ''echo "  kvCacheQuantization should be q4!"; exit 1''
      }

      ${
        if vmlxCustom.maxPromptTokens == 65536
        then ''echo "  maxPromptTokens = 65536: OK"''
        else ''echo "  maxPromptTokens should be 65536!"; exit 1''
      }

      echo ""
      echo "All vMLX option tests passed"
      touch $out
    '';
}
