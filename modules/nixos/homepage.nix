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
      services = [
        {
          Media = [
            (serviceLink "Jellyfin" "jellyfin.home.buildingbananas.com" "Media server")
            (serviceLink "Seerr" "seerr.home.buildingbananas.com" "Media requests")
            (serviceLink "Audiobookshelf" "audiobookshelf.home.buildingbananas.com" "Audiobooks and podcasts")
            (serviceLink "Shelfmark" "shelfmark.home.buildingbananas.com" "Book requests")
          ];
        }
        {
          Automation = [
            (serviceLink "Sonarr" "sonarr.home.buildingbananas.com" "TV automation")
            (serviceLink "Radarr" "radarr.home.buildingbananas.com" "Movie automation")
            (serviceLink "Prowlarr" "prowlarr.home.buildingbananas.com" "Indexer management")
            (serviceLink "Bazarr" "bazarr.home.buildingbananas.com" "Subtitle management")
            (serviceLink "Lidarr" "lidarr.home.buildingbananas.com" "Music automation")
          ];
        }
        {
          Downloads = [
            (serviceLink "SABnzbd" "sabnzbd.home.buildingbananas.com" "Usenet downloads")
            (serviceLink "Transmission" "transmission.home.buildingbananas.com" "Torrent downloads")
            (serviceLink "Autobrr" "autobrr.home.buildingbananas.com" "Download automation")
          ];
        }
        {
          Streaming = [
            (serviceLink "Sunshine" "sunshine.home.buildingbananas.com" "Moonlight game streaming")
          ];
        }
      ];
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

    myConfig.backup.paths = [{path = "/var/lib/homepage-dashboard";}];
  };
}
