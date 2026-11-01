# Caddy reverse proxy option tests
# Validates option defaults and custom values
{pkgs, ...}: let
  inherit (pkgs) lib;

  stubs = import ./stubs.nix {inherit pkgs;};

  caddyDefaults =
    (lib.evalModules {
      modules = stubs.caddy;
    }).config.myConfig.caddy;

  caddyCustom =
    (lib.evalModules {
      modules =
        stubs.caddy
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

  caddyInternalDnsConfig =
    (lib.evalModules {
      modules =
        stubs.caddy
        ++ [
          {
            config.myConfig.caddy.enable = true;
          }
        ];
    }).config;

  dnsmasqScript = caddyInternalDnsConfig.launchd.user.agents.dnsmasq.command;
  resolverText = caddyInternalDnsConfig.environment.etc."resolver/internal".text;
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

  caddyInternalDnsTest = pkgs.runCommand "test-caddy-internal-dns" {} ''
    echo "=== Testing generated internal DNS configuration ==="

    ${
      if resolverText == "nameserver 127.0.0.1\nport 5354\n"
      then ''echo "  macOS scoped resolver uses port 5354: OK"''
      else ''echo "  scoped resolver must use port 5354"; exit 1''
    }

    conf_file=$(grep -- '--conf-file=' ${dnsmasqScript} | cut -d '"' -f 2)
    if [ -z "$conf_file" ]; then
      echo "  dnsmasq launcher must reference its generated configuration"
      exit 1
    fi
    if ! grep -Fxq 'port=5354' "$conf_file"; then
      echo "  dnsmasq must listen on port 5354 to avoid mDNSResponder's port 5353"
      exit 1
    fi
    echo "  dnsmasq listens on port 5354: OK"
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
