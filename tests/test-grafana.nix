# Grafana tests for the native NixOS service and drlight observability host.
{
  pkgs,
  self ? null,
  ...
}: let
  inherit (pkgs) lib;
  stubs = import ./stubs.nix {inherit pkgs;};

  nixosGrafanaDefaults =
    (lib.evalModules {
      modules = stubs.nixosGrafana;
    }).config;

  nixosGrafanaEnabled =
    (lib.evalModules {
      modules =
        stubs.nixosGrafana
        ++ [
          {
            config.myConfig.grafana.enable = true;
            config.myConfig.prometheus.port = 9091;
            config.myConfig.loki.port = 3101;
          }
        ];
    }).config;

  nixosGrafanaDatasources = nixosGrafanaEnabled.services.grafana.provision.datasources.settings.datasources;
  findNixosGrafanaDatasource = name:
    lib.findFirst (datasource: datasource.name == name) null nixosGrafanaDatasources;
  nixosGrafanaDashboardPath =
    (builtins.head nixosGrafanaEnabled.services.grafana.provision.dashboards.settings.providers).options.path;

  nixosGrafanaSettings = nixosGrafanaEnabled.services.grafana.settings;
  nixosGrafanaAdminUser = nixosGrafanaSettings.security.admin_user or "";
  nixosGrafanaAdminPassword = nixosGrafanaSettings.security.admin_password or "";
  nixosGrafanaSecretKey = nixosGrafanaSettings.security.secret_key or "";
  nixosGrafanaPreStart = nixosGrafanaEnabled.systemd.services.grafana.preStart or "";
  nixosGrafanaSecrets = builtins.attrValues nixosGrafanaEnabled.myConfig.onepassword.secrets;
  nixosGrafanaUsernameSecretConfigured = lib.any (secret: secret.reference == "Grafana - Home/username" && secret.path == "/run/secrets/grafana-username" && secret.owner == "grafana" && secret.group == "grafana") nixosGrafanaSecrets;
  nixosGrafanaPasswordSecretConfigured = lib.any (secret: secret.reference == "Grafana - Home/password" && secret.path == "/run/secrets/grafana-password" && secret.owner == "grafana" && secret.group == "grafana") nixosGrafanaSecrets;

  nixosGrafanaArchetypeTest =
    if self == null
    then
      pkgs.runCommand "test-nixos-grafana-archetype-skipped" {} ''
        echo "Skipped: self not provided"
        touch $out
      ''
    else let
      drlight = self.nixosConfigurations.drlight.config;
      typeServer = self.nixosConfigurations.type-server.config;
      grafanaHost = drlight.services.caddy.virtualHosts."grafana.home.buildingbananas.com" or null;
      grafanaExecStart = drlight.systemd.services.grafana.serviceConfig.ExecStart;
      grafanaConfigFile = lib.last (lib.splitString " -config " grafanaExecStart);
      grafanaUnitRunsAsGrafana = drlight.systemd.services.grafana.serviceConfig.User == "grafana";
      darwinConfigurations = builtins.attrValues self.darwinConfigurations;
      grafanaAbsentFromDarwin = lib.all (machine: !(machine.config.launchd.daemons ? grafana) && !(machine.config.myConfig ? grafana)) darwinConfigurations;
    in
      pkgs.runCommand "test-nixos-grafana-archetype" {} ''
        echo "=== Testing Grafana archetype selection, ingress, and Darwin removal ==="

        ${
          if drlight.myConfig.grafana.enable && drlight.services.grafana.enable
          then ''echo "drlight type-observability enables native Grafana: OK"''
          else ''echo "FAIL: drlight type-observability must enable native Grafana"; exit 1''
        }

        ${
          if !(typeServer.services.grafana.enable or false)
          then ''echo "type-server does not run Grafana: OK"''
          else ''echo "FAIL: Grafana must stay disabled on type-server"; exit 1''
        }

        ${
          if grafanaHost != null && lib.hasInfix "reverse_proxy http://127.0.0.1:3000" (grafanaHost.extraConfig or "")
          then ''echo "grafana.home.buildingbananas.com proxies to loopback Grafana: OK"''
          else ''echo "FAIL: drlight Grafana Caddy host must proxy to http://127.0.0.1:3000"; exit 1''
        }

        ${
          if !(builtins.elem 3000 (drlight.networking.firewall.allowedTCPPorts or []))
          then ''echo "Grafana port 3000 is not opened directly in the host firewall: OK"''
          else ''echo "FAIL: Grafana port 3000 must remain loopback-only behind Caddy"; exit 1''
        }

        ${
          if grafanaAbsentFromDarwin
          then ''echo "Darwin configurations have no Grafana option or launchd service: OK"''
          else ''echo "FAIL: Darwin configurations must not contain Grafana"; exit 1''
        }

        ${
          if grafanaUnitRunsAsGrafana
          then ''echo "Grafana systemd unit runs as the file owner grafana: OK"''
          else ''echo "FAIL: Grafana must run as grafana so its secret key is owned by that service user"; exit 1''
        }

        GRAFANA_CONFIG=${grafanaConfigFile}
        for provider in '$__file{/run/secrets/grafana-username}' '$__file{/run/secrets/grafana-password}' '$__file{/var/lib/grafana/secret_key}'; do
          if grep -Fq "$provider" "$GRAFANA_CONFIG"; then
            echo "generated Grafana config contains runtime file provider $provider: OK"
          else
            echo "FAIL: generated Grafana config is missing runtime file provider $provider"; exit 1
          fi
        done

        echo "All NixOS Grafana archetype tests passed"
        touch $out
      '';
in {
  nixosGrafanaOptionsTest = pkgs.runCommand "test-nixos-grafana-options" {} ''
    echo "=== Testing NixOS Grafana default state ==="

    ${
      if !(nixosGrafanaDefaults.myConfig.grafana.enable or false)
      then ''echo "myConfig.grafana.enable defaults to false: OK"''
      else ''echo "FAIL: Grafana should default to disabled"; exit 1''
    }

    ${
      if !(nixosGrafanaDefaults.services.grafana.enable or false)
      then ''echo "services.grafana.enable defaults to false: OK"''
      else ''echo "FAIL: native Grafana service should default to disabled"; exit 1''
    }

    echo "NixOS Grafana default-state tests passed"
    touch $out
  '';

  nixosGrafanaServiceTest = pkgs.runCommand "test-nixos-grafana-service" {} ''
    echo "=== Testing native NixOS Grafana listener ==="

    ${
      if nixosGrafanaEnabled.services.grafana.enable
      then ''echo "services.grafana.enable = true when selected: OK"''
      else ''echo "FAIL: enabling myConfig.grafana must enable services.grafana"; exit 1''
    }

    ${
      if nixosGrafanaEnabled.services.grafana.settings.server.http_addr == "127.0.0.1"
      then ''echo "Grafana binds to loopback for Caddy proxying: OK"''
      else ''echo "FAIL: Grafana must bind to 127.0.0.1"; exit 1''
    }

    ${
      if nixosGrafanaEnabled.services.grafana.settings.server.http_port == 3000
      then ''echo "Grafana uses native services.grafana port 3000: OK"''
      else ''echo "FAIL: Grafana must listen on port 3000"; exit 1''
    }

    ${
      if !(builtins.elem 3000 (nixosGrafanaEnabled.networking.firewall.allowedTCPPorts or []))
      then ''echo "Grafana port 3000 is not directly exposed by the firewall: OK"''
      else ''echo "FAIL: Grafana port 3000 must not be opened directly"; exit 1''
    }

    echo "Native NixOS Grafana listener tests passed"
    touch $out
  '';

  nixosGrafanaDatasourcesTest = pkgs.runCommand "test-nixos-grafana-datasources" {} ''
    echo "=== Testing native NixOS Grafana datasources ==="

    ${
      if
        findNixosGrafanaDatasource "Prometheus"
        != null
        && (findNixosGrafanaDatasource "Prometheus").url == "http://127.0.0.1:9091"
      then ''echo "Prometheus datasource targets the local configured port 9091: OK"''
      else ''echo "FAIL: Prometheus datasource must target http://127.0.0.1:9091"; exit 1''
    }

    ${
      if
        findNixosGrafanaDatasource "Loki"
        != null
        && (findNixosGrafanaDatasource "Loki").url == "http://127.0.0.1:3101"
      then ''echo "Loki datasource targets the local configured port 3101: OK"''
      else ''echo "FAIL: Loki datasource must target http://127.0.0.1:3101"; exit 1''
    }

    echo "Native NixOS Grafana datasource tests passed"
    touch $out
  '';

  nixosGrafanaDashboardTest =
    pkgs.runCommand "test-nixos-grafana-dashboard" {
      nativeBuildInputs = [pkgs.jq];
    } ''
      echo "=== Testing system-overview dashboard and central labels ==="

      DASHBOARD_DIR=${nixosGrafanaDashboardPath}
      DASHBOARD=$(find "$DASHBOARD_DIR" -type f -name '*.json' -print -quit)
      if [ -z "$DASHBOARD" ]; then
        echo "FAIL: Grafana must provision a system-overview dashboard JSON"; exit 1
      fi

      if jq -e '.title | contains("System Overview")' "$DASHBOARD" > /dev/null; then
        echo "system-overview dashboard is provisioned: OK"
      else
        echo "FAIL: provisioned dashboard title must identify System Overview"; exit 1
      fi

      PROMETHEUS_QUERY_COUNT=$(jq '[.. | objects | select(.datasource.type? == "prometheus") | .expr? // empty] | length' "$DASHBOARD")
      if [ "$PROMETHEUS_QUERY_COUNT" -ge 3 ] && \
         jq -e '[.. | objects | select(.datasource.type? == "prometheus") | .expr? // empty] | all(.[]; contains("job=\"node\""))' "$DASHBOARD" > /dev/null; then
        echo "Prometheus dashboard queries use the central node job label: OK"
      else
        echo "FAIL: system metrics queries must select the central job=\"node\" label"; exit 1
      fi

      if jq -e '[.. | objects | select(.datasource.type? == "loki") | .expr? // empty] | any(contains("host") and contains("service") and contains("severity"))' "$DASHBOARD" > /dev/null; then
        echo "Loki dashboard query uses the central host/service/severity labels: OK"
      else
        echo "FAIL: log query must match Vector's host, service, and severity labels"; exit 1
      fi

      echo "System-overview dashboard tests passed"
      touch $out
    '';

  nixosGrafanaSecretsTest = pkgs.runCommand "test-nixos-grafana-secrets" {} ''
    echo "=== Testing runtime Grafana credentials and secret key ==="

    ${
      if nixosGrafanaUsernameSecretConfigured && nixosGrafanaPasswordSecretConfigured
      then ''echo "exact unqualified Grafana opnix references map to Grafana-owned runtime secret files: OK"''
      else ''echo "FAIL: Grafana - Home/username and Grafana - Home/password must map to their exact /run/secrets paths with Grafana ownership"; exit 1''
    }

    ${
      if
        nixosGrafanaAdminUser
        == "$__file{/run/secrets/grafana-username}"
        && nixosGrafanaAdminPassword == "$__file{/run/secrets/grafana-password}"
      then ''echo "Grafana credentials use exact runtime file providers, not embedded values: OK"''
      else ''echo "FAIL: Grafana settings must use the exact /run/secrets username and password file providers"; exit 1''
    }

    ${
      if
        !(lib.hasInfix "/nix/store" nixosGrafanaAdminUser)
        && !(lib.hasInfix "/nix/store" nixosGrafanaAdminPassword)
      then ''echo "Grafana credential providers exclude /nix/store paths: OK"''
      else ''echo "FAIL: Grafana credential providers must not reference /nix/store"; exit 1''
    }

    ${
      if nixosGrafanaSecretKey == "$__file{/var/lib/grafana/secret_key}"
      then ''echo "Grafana secret_key uses the persistent runtime file provider: OK"''
      else ''echo "FAIL: Grafana security.secret_key must use $__file{/var/lib/grafana/secret_key}"; exit 1''
    }

    ${
      if
        lib.hasInfix "if [ ! -e /var/lib/grafana/secret_key ]" nixosGrafanaPreStart
        && lib.hasInfix "openssl" nixosGrafanaPreStart
        && lib.hasInfix "chmod 0600" nixosGrafanaPreStart
        && lib.hasInfix "mv" nixosGrafanaPreStart
      then ''echo "service startup creates a cryptographically random persistent key once with restrictive permissions: OK"''
      else ''echo "FAIL: Grafana startup must create a persistent random key only when absent and set restrictive permissions"; exit 1''
    }

    echo "NixOS Grafana runtime secret tests passed"
    touch $out
  '';

  inherit nixosGrafanaArchetypeTest;
}
