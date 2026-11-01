# Homepage dashboard for NixOS media services.
{
  config,
  lib,
  ...
}:
with lib; let
  cfg = config.myConfig.homepage;
  serviceLink = name: host: description: {
    ${name} = {
      href = "https://${host}";
      inherit description;
    };
  };
in {
  options.myConfig.homepage.enable = mkEnableOption "Homepage service dashboard";

  config = mkIf cfg.enable {
    services.homepage-dashboard = {
      enable = true;
      listenPort = 8082;
      allowedHosts = "dashboard.home.buildingbananas.com";
      openFirewall = false;
      services =
        [
          {
            Media = [
              (serviceLink "Jellyfin" "jellyfin.home.buildingbananas.com" "Media server")
            ];
          }
        ]
        ++ optional (config.services.grafana.enable or false) {
          Monitoring = [
            (serviceLink "Grafana" "grafana.home.buildingbananas.com" "System monitoring")
          ];
        };
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
  };
}
