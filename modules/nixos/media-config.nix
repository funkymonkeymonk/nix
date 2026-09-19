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
  authHeader = ''MediaBrowser Client="NixOS", Device="zero", DeviceId="nixos-zero", Version="1.0", Token="$token"'';
in {
  options.myConfig.mediaConfig.enable = mkEnableOption "declarative media application configuration";

  config = mkIf cfg.enable {
    systemd.services.jellyfin-declarative-config = {
      description = "Apply declarative Jellyfin configuration";
      wantedBy = ["multi-user.target"];
      after = ["jellyfin.service" "opnix-secrets.service"];
      requires = ["jellyfin.service" "opnix-secrets.service"];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        set -eu
        base_url=${baseUrl}
        password_file=/run/secrets/jellyfin-admin-password
        for attempt in $(seq 1 60); do
          startup_status="$(${pkgs.curl}/bin/curl -sS -o /dev/null -w '%{http_code}' "$base_url/Startup/Configuration" || true)"
          if [ "$startup_status" != "000" ]; then
            break
          fi
          sleep 1
        done

        password="$(${pkgs.coreutils}/bin/cat "$password_file")"
        startup_status="$(${pkgs.curl}/bin/curl -sS -o /dev/null -w '%{http_code}' "$base_url/Startup/Configuration")"
        if [ "$startup_status" = "200" ]; then
          ${pkgs.curl}/bin/curl -fsS -X POST "$base_url/Startup/Configuration" \
            -H 'Content-Type: application/json' \
            -d '{"ServerName":"zero","UICulture":"en-US","MetadataCountryCode":"US","PreferredMetadataLanguage":"en-us"}'
          ${pkgs.curl}/bin/curl -fsS -X POST "$base_url/Startup/User" \
            -H 'Content-Type: application/json' \
            -d "$(${pkgs.jq}/bin/jq -cn --arg password "$password" '{Name:"monkey",Password:$password}')"
          ${pkgs.curl}/bin/curl -fsS -X POST "$base_url/Startup/Complete"
        fi

        auth_response="$(${pkgs.curl}/bin/curl -fsS -X POST "$base_url/Users/AuthenticateByName" \
          -H 'Content-Type: application/json' \
          -H 'X-Emby-Authorization: MediaBrowser Client="NixOS", Device="zero", DeviceId="nixos-zero", Version="1.0"' \
          -d "$(${pkgs.jq}/bin/jq -cn --arg password "$password" '{Username:"monkey",Pw:$password}')")"
        token="$(${pkgs.jq}/bin/jq -er .AccessToken <<<"$auth_response")"

        for library in \
          "Movies|movies|/srv/media/library/movies" \
          "Shows|tvshows|/srv/media/library/shows" \
          "Music|music|/srv/media/library/music"; do
          IFS='|' read -r name collection path <<<"$library"
          if ! ${pkgs.curl}/bin/curl -fsS "$base_url/Library/VirtualFolders" \
            -H "X-Emby-Authorization: ${authHeader}" \
            | ${pkgs.jq}/bin/jq -e --arg name "$name" 'any(.[]; .Name == $name)' >/dev/null; then
            ${pkgs.curl}/bin/curl -fsS -X POST "$base_url/Library/VirtualFolders?name=$name&collectionType=$collection&paths=$path&refreshLibrary=true" \
              -H "X-Emby-Authorization: ${authHeader}"
          fi
        done
      '';
    };
  };
}
