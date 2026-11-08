{
  lib,
  pkgs,
  ...
}: let
  configPath = "/run/secrets/ultra-media-sync-config.json";
  keyPath = "/run/secrets/ultra-media-sync-key";
in {
  users.users.ultra-sync = {
    isSystemUser = true;
    group = "users";
    description = "Pull media into the local library";
  };

  myConfig.onepassword.secrets = {
    ultraMediaSyncConfig = {
      reference = "Ultra Media Sync Config/config";
      path = configPath;
      mode = "0400";
      owner = "ultra-sync";
      group = "users";
      services = ["ultra-media-sync"];
    };
    ultraMediaSyncKey = {
      reference = "Ultra Media Sync Key/private key";
      path = keyPath;
      mode = "0400";
      owner = "ultra-sync";
      group = "users";
      services = ["ultra-media-sync"];
    };
  };

  systemd.services.ultra-media-sync = {
    # Let an in-flight transfer finish across a NixOS switch; the next run uses the new unit.
    restartIfChanged = false;
    description = "Pull configured media into the local library";
    after = ["network-online.target" "zfs-mount.service" "opnix-secrets.service"];
    wants = ["network-online.target"];
    requires = ["zfs-mount.service" "opnix-secrets.service"];
    unitConfig.ConditionPathIsMountPoint = "/srv/media";
    path = [pkgs.coreutils pkgs.jq];
    serviceConfig = {
      Type = "oneshot";
      User = "ultra-sync";
      Group = "users";
      UMask = "0002";
    };
    script = ''
      set -euo pipefail
      umask 0002

      config_file=${lib.escapeShellArg configPath}
      key_file=${lib.escapeShellArg keyPath}
      host="$(jq -r '.host' "$config_file")"
      username="$(jq -r '.username' "$config_file")"
      port="$(jq -r '.port' "$config_file")"
      mediaRoot="$(jq -r '.mediaRoot' "$config_file")"
      knownHosts="$(jq -r '.knownHosts' "$config_file")"

      if [ -z "$host" ] || [ -z "$username" ] || [ -z "$knownHosts" ] || [ ! -r "$key_file" ]; then
        echo "Ultra media sync configuration or private key is unavailable" >&2
        exit 1
      fi
      case "$port" in
        ""|*[!0-9]*)
          echo "Ultra media sync SSH port must be numeric" >&2
          exit 1
          ;;
      esac
      case "$mediaRoot" in
        /*) ;;
        *)
          echo "Ultra media sync mediaRoot must be an absolute path" >&2
          exit 1
          ;;
      esac
      jq -e '.mappings | type == "array"' "$config_file" >/dev/null
      mediaRoot="''${mediaRoot%/}"

      mapping_file="$(mktemp)"
      known_hosts_file="$(mktemp)"
      trap 'rm -f "$mapping_file" "$known_hosts_file"' EXIT
      jq --raw-output0 '.mappings[] | .source, .destination' "$config_file" > "$mapping_file"

      chmod 600 "$known_hosts_file"
      printf '%s\n' "$knownHosts" > "$known_hosts_file"
      if [ "$port" = "22" ]; then
        known_hosts_alias="$host"
      else
        known_hosts_alias="[$host]:$port"
      fi
      if ! ${pkgs.openssh}/bin/ssh-keygen -F "$known_hosts_alias" -f "$known_hosts_file" >/dev/null; then
        echo "Ultra media sync pinned host key is missing for the configured SSH endpoint" >&2
        exit 1
      fi

      ssh_args=(
        -i "$key_file"
        -p "$port"
        -o BatchMode=yes
        -o IdentitiesOnly=yes
        -o StrictHostKeyChecking=yes
        -o "UserKnownHostsFile=$known_hosts_file"
        -o GlobalKnownHostsFile=/dev/null
      )
      remote="$username@$host"
      quote_remote_shell() {
        local quoted
        printf -v quoted '%q' "$1"
        printf '%s' "$quoted"
      }
      quoted_media_root="$(quote_remote_shell "$mediaRoot")"
      remote_listing_command="find $quoted_media_root -mindepth 1 -maxdepth 1 -type d -printf '%f\\0'"
      "${pkgs.openssh}/bin/ssh" "''${ssh_args[@]}" "$remote" "$remote_listing_command" |

        while IFS= read -r -d ''' remote_folder; do
          if [ -n "$remote_folder" ] && ! jq -e --arg folder "$remote_folder" 'any(.mappings[]; (.source | split("/")[0]) == $folder)' "$config_file" >/dev/null; then
            printf 'Unconfigured remote media folder: %s\n' "$remote_folder"
          fi
        done

      ssh_command="${pkgs.openssh}/bin/ssh -i $key_file -p $port -o BatchMode=yes -o IdentitiesOnly=yes -o StrictHostKeyChecking=yes -o UserKnownHostsFile=$known_hosts_file -o GlobalKnownHostsFile=/dev/null"
      while IFS= read -r -d ''' source && IFS= read -r -d ''' destination; do
        case "$source" in
          ""|/*|.|..|../*|*/../*|*/..|./*|*/./*)
            echo "Ultra media sync mapping source must be a relative subpath" >&2
            exit 1
            ;;
        esac
        case "$destination" in
          ""|.|..|*/*)
            echo "Ultra media sync destination must be a library root name" >&2
            exit 1
            ;;
        esac
        remote_source="$mediaRoot/$source/"
        local_destination="/srv/media/$destination"
        "${pkgs.rsync}/bin/rsync" \
          --recursive \
          --times \
          --omit-dir-times \
          --no-perms \
          --chmod=Du=rwx,Dg=rwx,Do=rx,Fu=rw,Fg=rw,Fo=r,ugo-s,o-t \
          --protect-args \
          --bwlimit=20000 \
          --partial-dir=.rsync-partial \
          --itemize-changes \
          --out-format='%i %n%L' \
          --rsh="$ssh_command" \
          "$remote:$remote_source" \
          "$local_destination/"
      done < "$mapping_file"
    '';
  };

  systemd.timers.ultra-media-sync = {
    wantedBy = ["timers.target"];
    timerConfig = {
      OnCalendar = "hourly";
      # Do not launch a long catch-up transfer while NixOS is activating a new generation.
      Persistent = false;
      RandomizedDelaySec = "5m";
      Unit = "ultra-media-sync.service";
    };
  };
}
