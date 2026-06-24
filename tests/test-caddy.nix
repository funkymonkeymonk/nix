# Caddy reverse proxy option tests
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

  caddyDefaults =
    (lib.evalModules {
      modules = stubModules;
    }).config.myConfig.caddy;

  caddyCustom =
    (lib.evalModules {
      modules =
        stubModules
        ++ [
          {
            config.myConfig.caddy = {
              enable = true;
              port = 8080;
              dataDir = "/var/lib/caddy";
              hosts = {
                "app.internal" = "localhost:9000";
                "api.internal" = "localhost:9001";
              };
            };
          }
        ];
    }).config.myConfig.caddy;
in {
  caddyOptionsTest = pkgs.runCommand "test-caddy-options" {} ''
    echo "=== Testing Caddy Option Defaults ==="

    ${
      if !caddyDefaults.enable
      then ''echo "  enable default = false: OK"''
      else ''echo "  enable should default to false!"; exit 1''
    }

    ${
      if caddyDefaults.port == 80
      then ''echo "  port default = 80: OK"''
      else ''echo "  port should default to 80!"; exit 1''
    }

    ${
      if caddyDefaults.dataDir == "$HOME/.local/share/caddy"
      then ''echo "  dataDir default = \$HOME/.local/share/caddy: OK"''
      else ''echo "  dataDir should default to \$HOME/.local/share/caddy!"; exit 1''
    }

    ${
      if caddyDefaults.hosts == {}
      then ''echo "  hosts default = {}: OK"''
      else ''echo "  hosts should default to {}!"; exit 1''
    }

    echo "All Caddy option defaults verified"
    touch $out
  '';

  caddyCustomOptionsTest = pkgs.runCommand "test-caddy-custom-options" {} ''
    echo "=== Testing Caddy Custom Options ==="

    ${
      if caddyCustom.enable
      then ''echo "  enable = true: OK"''
      else ''echo "  enable should be true!"; exit 1''
    }

    ${
      if caddyCustom.port == 8080
      then ''echo "  port = 8080: OK"''
      else ''echo "  port should be 8080!"; exit 1''
    }

    ${
      if caddyCustom.dataDir == "/var/lib/caddy"
      then ''echo "  dataDir = /var/lib/caddy: OK"''
      else ''echo "  dataDir should be /var/lib/caddy!"; exit 1''
    }

    ${
      if caddyCustom.hosts ? "app.internal"
      then ''echo "  hosts.app.internal defined: OK"''
      else ''echo "  hosts.app.internal should be defined!"; exit 1''
    }

    ${
      if caddyCustom.hosts."app.internal" == "localhost:9000"
      then ''echo "  hosts.app.internal = localhost:9000: OK"''
      else ''echo "  hosts.app.internal should be localhost:9000!"; exit 1''
    }

    ${
      if caddyCustom.hosts ? "api.internal"
      then ''echo "  hosts.api.internal defined: OK"''
      else ''echo "  hosts.api.internal should be defined!"; exit 1''
    }

    echo "All Caddy custom options verified"
    touch $out
  '';
}
