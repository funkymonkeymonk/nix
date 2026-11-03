# Homepage dashboard for NixOS media services.
{
  config,
  lib,
  ...
}:
with lib; let
  cfg = config.myConfig.homepage;
  caddyApps = config.myConfig.caddy.apps or {};
  homepageApps = filterAttrs (_: app: app.homepage.enable) caddyApps;
  homepageEntries =
    mapAttrsToList (name: app: let
      presentation = app.homepage;
      title =
        if presentation.title == null
        then name
        else presentation.title;
      service =
        {
          href = "https://${app.host}";
        }
        // optionalAttrs (presentation.description != "") {
          inherit (presentation) description;
        }
        // optionalAttrs (presentation.widgets != []) {
          widgets = presentation.widgets;
        };
    in {
      group = presentation.group;
      entry = {${title} = service;};
    })
    homepageApps;
  groupedHomepageEntries = foldl' (groups: item:
    groups
    // {
      ${item.group} = (groups.${item.group} or []) ++ [item.entry];
    }) {}
  homepageEntries;
  homepageServices = mapAttrsToList (group: entries: {${group} = entries;}) groupedHomepageEntries;
  hasGrafanaHomepageWidget =
    any
    (widget: (widget.type or null) == "grafana")
    (caddyApps.grafana.homepage.widgets or []);
in {
  options.myConfig.homepage.enable = mkEnableOption "Homepage service dashboard";

  config = mkIf cfg.enable {
    services.homepage-dashboard = {
      enable = true;
      listenPort = 8082;
      allowedHosts = "dashboard.home.buildingbananas.com,drlight.uaru-daggertooth.ts.net:8443";
      openFirewall = false;
      services = homepageServices;
      widgets = [
        {
          resources = {
            cpu = true;
            memory = true;
            disk = "/";
          };
        }
        {
          datetime = {
            format = "HH:mm:ss";
          };
        }
      ];
    };

    systemd.services.homepage-dashboard = mkIf hasGrafanaHomepageWidget {
      after = ["opnix-secrets.service"];
      requires = ["opnix-secrets.service"];
      serviceConfig.LoadCredential = [
        "grafana-username:/run/secrets/grafana-username"
        "grafana-password:/run/secrets/grafana-password"
      ];
      environment = {
        HOMEPAGE_FILE_GRAFANA_USERNAME = "%d/grafana-username";
        HOMEPAGE_FILE_GRAFANA_PASSWORD = "%d/grafana-password";
      };
    };

    myConfig.onepassword.secrets.grafanaUsername.services = mkIf hasGrafanaHomepageWidget ["homepage-dashboard"];
    myConfig.onepassword.secrets.grafanaPassword.services = mkIf hasGrafanaHomepageWidget ["homepage-dashboard"];
  };
}
