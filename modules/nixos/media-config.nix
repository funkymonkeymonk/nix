# Declarative first-run and library configuration for Jellyfin.
{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.myConfig.mediaConfig;
  baseUrl = "http://127.0.0.1:8096";
in {
  options.myConfig.mediaConfig.enable = mkEnableOption "declarative media application configuration";

  config = mkIf cfg.enable {
    systemd.services.jellyfin-declarative-config = {
      description = "Apply declarative Jellyfin configuration";
      wantedBy = ["multi-user.target"];
      after = ["jellyfin.service" "opnix-secrets.service"];
      requires = ["jellyfin.service" "opnix-secrets.service"];
      unitConfig.RequiresMountsFor = ["/srv/media"];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        set -eu
        base_url=${baseUrl}
        auth_header='MediaBrowser Client="NixOS", Device="zero", DeviceId="nixos-zero", Version="1.0", Token='
        password_file=/run/secrets/jellyfin-admin-password
        for attempt in $(seq 1 60); do
          startup_status="$(${pkgs.curl}/bin/curl -sS -o /dev/null -w '%{http_code}' "$base_url/Startup/Configuration" || true)"
          case "$startup_status" in
            200|401|404) break ;;
          esac
          sleep 1
        done

        password="$(${pkgs.coreutils}/bin/cat "$password_file")"
        startup_status="$(${pkgs.curl}/bin/curl -sS -o /dev/null -w '%{http_code}' "$base_url/Startup/Configuration")"
        if [ "$startup_status" = "200" ]; then
          ${pkgs.curl}/bin/curl -fsS -X POST "$base_url/Startup/Configuration" \
            -H 'Content-Type: application/json' \
            -d '{"ServerName":"zero","UICulture":"en-US","MetadataCountryCode":"US","PreferredMetadataLanguage":"en-us"}'
          ${pkgs.curl}/bin/curl -fsS "$base_url/Startup/User" >/dev/null
          ${pkgs.curl}/bin/curl -fsS -X POST "$base_url/Startup/User" \
            -H 'Content-Type: application/json' \
            -d "$(${pkgs.jq}/bin/jq -cn --arg password "$password" '{Name:"monkey",Password:$password}')"
          ${pkgs.curl}/bin/curl -fsS -X POST "$base_url/Startup/Complete" \
            -H 'Content-Type: application/json' \
            -d '{}'
        fi

        api_status=""
        for attempt in $(seq 1 60); do
          api_status="$(${pkgs.curl}/bin/curl -sS -o /dev/null -w '%{http_code}' "$base_url/System/Info/Public" || true)"
          [ "$api_status" = "200" ] && break
          sleep 1
        done
        [ "$api_status" = "200" ]

        auth_response="$(${pkgs.curl}/bin/curl -fsS -X POST "$base_url/Users/AuthenticateByName" \
          -H 'Content-Type: application/json' \
          -H 'Authorization: MediaBrowser Client="NixOS", Device="zero", DeviceId="nixos-zero", Version="1.0"' \
          -d "$(${pkgs.jq}/bin/jq -cn --arg password "$password" '{Username:"jellyfin",Pw:$password}')")"
        token="$(${pkgs.jq}/bin/jq -er .AccessToken <<<"$auth_response")"

        for library in \
          "Movies|movies|/srv/media/library/movies" \
          "Shows|tvshows|/srv/media/library/shows" \
          "Music|music|/srv/media/library/music"; do
          IFS='|' read -r name collection path <<<"$library"
          if ! ${pkgs.curl}/bin/curl -fsS "$base_url/Library/VirtualFolders" \
            -H "Authorization: $auth_header$token" \
            | ${pkgs.jq}/bin/jq -e --arg name "$name" 'any(.[]; .Name == $name)' >/dev/null; then
            ${pkgs.curl}/bin/curl -fsS -X POST "$base_url/Library/VirtualFolders?name=$name&collectionType=$collection&paths=$path&refreshLibrary=true" \
              -H "Authorization: $auth_header$token"
          fi
        done
      '';
    };
  };
}
