# SearXNG option tests
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

  searxngDefaults =
    (lib.evalModules {
      modules = stubModules;
    }).config.myConfig.searxng;

  searxngCustom =
    (lib.evalModules {
      modules =
        stubModules
        ++ [
          {
            config.myConfig.searxng = {
              enable = true;
              port = 9090;
              secretKey = "my-secret-key";
            };
          }
        ];
    }).config.myConfig.searxng;
in {
  searxngOptionsTest = pkgs.runCommand "test-searxng-options" {} ''
    echo "=== Testing SearXNG Option Defaults ==="

    ${
      if !searxngDefaults.enable
      then ''echo "  enable default = false: OK"''
      else ''echo "  enable should default to false!"; exit 1''
    }

    ${
      if searxngDefaults.port == 8080
      then ''echo "  port default = 8080: OK"''
      else ''echo "  port should default to 8080!"; exit 1''
    }

    ${
      if searxngDefaults.secretKey == ""
      then ''echo "  secretKey default = empty: OK"''
      else ''echo "  secretKey should default to empty!"; exit 1''
    }

    echo "All SearXNG option defaults verified"
    touch $out
  '';

  searxngCustomOptionsTest = pkgs.runCommand "test-searxng-custom-options" {} ''
    echo "=== Testing SearXNG Custom Options ==="

    ${
      if searxngCustom.enable
      then ''echo "  enable = true: OK"''
      else ''echo "  enable should be true!"; exit 1''
    }

    ${
      if searxngCustom.port == 9090
      then ''echo "  port = 9090: OK"''
      else ''echo "  port should be 9090!"; exit 1''
    }

    ${
      if searxngCustom.secretKey == "my-secret-key"
      then ''echo "  secretKey = my-secret-key: OK"''
      else ''echo "  secretKey should be my-secret-key!"; exit 1''
    }

    echo "All SearXNG custom options verified"
    touch $out
  '';
}
