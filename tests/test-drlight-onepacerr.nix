{
  pkgs,
  self ? null,
  ...
}: let
  inherit (pkgs) lib;

  skipped = pkgs.runCommand "test-drlight-onepacerr-skipped" {} ''
    echo "Skipped: self not provided"
    touch $out
  '';

  checks =
    if self == null
    then null
    else let
      drlight = self.nixosConfigurations.drlight.config;
      drlightWithOnePacerr =
        (self.nixosConfigurations.drlight.extendModules {
          modules = [
            {
              myConfig.onePacerr = {
                enable = true;
                autoStart = true;
                jellyfinLibraryName = "Shows";
                libraryHostPath = "/srv/media/test-library/One Pace";
                libraryContainerPath = "/library/One Pace";
              };
            }
          ];
        }).config;
      configuredDrlight = drlightWithOnePacerr;
      onepacerr = configuredDrlight.myConfig.onePacerr or {};
      users = configuredDrlight.users.users or {};
      groups = configuredDrlight.users.groups or {};
      onepacerrUser = users.onepacerr or {};
      container = (configuredDrlight.virtualisation.oci-containers.containers or {}).onepacerr or {};
      containerEnvironment = container.environment or {};
      containerEnvironmentFiles = map toString (container.environmentFiles or []);
      containerService = configuredDrlight.systemd.services."podman-onepacerr" or {};
      containerServiceUnitConfig = containerService.unitConfig or {};
      containerServiceConfig = containerService.serviceConfig or {};
      containerStartPre = containerServiceConfig.ExecStartPre or [];
      jellyfinSecrets = configuredDrlight.myConfig.onepassword.secrets or {};
      jellyfinUsernameSecret = jellyfinSecrets.jellyfinAdminUsername or {};
      jellyfinPasswordSecret = jellyfinSecrets.jellyfinAdminPassword or {};
      libraryHostPath = onepacerr.libraryHostPath or "";
      libraryContainerPath = onepacerr.libraryContainerPath or "";
      jellyfinLibraryName = onepacerr.jellyfinLibraryName or "";
      seriesName = onepacerr.seriesName or "";
      groupGid = toString (groups.users.gid or 100);
      arrStagingRoot = "/srv/media/.arr-staging";
      envScriptSource = "${toString ../modules/nixos}/onepacerr-env.py";
      sharedMediaScripts = builtins.readDir ../modules/nixos/scripts;
      envScript =
        if builtins.pathExists envScriptSource
        then
          builtins.path {
            path = envScriptSource;
            name = "onepacerr-env-script";
          }
        else null;
      assertTrue = name: condition:
        if condition
        then ''echo "  ${name}: OK"''
        else ''echo ${lib.escapeShellArg "FAIL: ${name}"}; failures=1'';
      assertEqual = name: expected: actual: assertTrue name (expected == actual);
    in
      pkgs.runCommand "test-drlight-onepacerr"
      {nativeBuildInputs = [pkgs.coreutils pkgs.gnugrep pkgs.python3];}
      ''
        failures=0
        echo "=== Testing Drlight OnePacerr configuration ==="

        ${assertTrue "OnePacerr is disabled on Drlight until preflight passes" (!(drlight.myConfig.onePacerr.enable or false) && !(drlight.myConfig.onePacerr.autoStart or false) && !(drlight.virtualisation.oci-containers.containers ? onepacerr) && !(drlight.users.users ? onepacerr))}
        ${assertTrue "OnePacerr opt-in enabled for its configuration test" (onepacerr.enable or false)}
        ${assertTrue "Opt-in OnePacerr can auto-start after preflight" (container.autoStart or false)}
        ${assertEqual "OnePacerr container uses Podman" "podman" configuredDrlight.virtualisation.oci-containers.backend}
        ${assertEqual "OnePacerr uses pinned v1.8.16 image" "ghcr.io/eltharynd/onepacerr:v1.8.16" (container.image or null)}
        ${assertEqual "OnePacerr host user has UID 1500" 1500 (onepacerrUser.uid or null)}
        ${assertEqual "OnePacerr runs as dedicated UID 1500 and users group" "1500:${groupGid}" (container.user or null)}
        ${assertEqual "OnePacerr mounts exactly the configured library subtree" ["${libraryHostPath}:${libraryContainerPath}:rw"] (container.volumes or [])}
        ${assertTrue "OnePacerr host library path is a nested media subtree" (lib.hasPrefix "/srv/media/" libraryHostPath && libraryHostPath != "/srv/media" && libraryHostPath != "/srv/media/shows")}
        ${assertEqual "OnePacerr Jellyfin library name is configured" jellyfinLibraryName (containerEnvironment.JELLYFIN_LIBRARY_NAME or null)}
        ${assertEqual "OnePacerr Jellyfin URL uses Podman's host gateway" "http://host.containers.internal:8096" (containerEnvironment.JELLYFIN_URL or null)}
        ${assertEqual "OnePacerr uses Jellyfin as its media server" "jellyfin" (containerEnvironment.LIBRARY_MEDIA_SERVER or null)}
        ${assertEqual "OnePacerr series name is configured" seriesName (containerEnvironment.LIBRARY_SERIES_NAME or null)}
        ${assertEqual "OnePacerr doesn't create a missing Jellyfin series" "false" (containerEnvironment.LIBRARY_CREATE_SHOW_IF_NOT_FOUND or null)}
        ${assertEqual "OnePacerr initial mode skips downloads" "true" (containerEnvironment.PIPELINE_SKIP_DOWNLOADS or null)}
        ${assertEqual "OnePacerr organizes existing files" "false" (containerEnvironment.PIPELINE_SKIP_ORGANIZE_PRESENT_FILES or null)}
        ${assertEqual "OnePacerr updates existing Jellyfin metadata" "false" (containerEnvironment.PIPELINE_SKIP_UPDATE_METADATA_PRESENT_FILES or null)}
        ${assertTrue "OnePacerr has no Transmission credentials or endpoint" (!(containerEnvironment ? TORRENT_URL) && !(containerEnvironment ? TORRENT_USER) && !(containerEnvironment ? TORRENT_PASSWORD) && !(containerEnvironment ? TORRENT_CLIENT))}
        ${assertEqual "OnePacerr reads its credential env file at runtime" ["/run/onepacerr/credentials.env"] containerEnvironmentFiles}
        ${assertTrue "OnePacerr renders credentials before Podman starts" (lib.any (command: lib.hasInfix "render-onepacerr-credentials" (toString command)) containerStartPre)}
        ${assertTrue "Jellyfin credentials are not embedded in OCI environment literals" (!(containerEnvironment ? JELLYFIN_USERNAME) && !(containerEnvironment ? JELLYFIN_PASSWORD))}
        ${assertTrue "Jellyfin Opnix references are unqualified" ((jellyfinUsernameSecret.reference or null) == "Jellyfin/username" && (jellyfinPasswordSecret.reference or null) == "Jellyfin/password")}
        ${assertTrue "Opnix restarts OnePacerr when Jellyfin credentials rotate" (builtins.elem "podman-onepacerr" (jellyfinUsernameSecret.services or []) && builtins.elem "podman-onepacerr" (jellyfinPasswordSecret.services or []))}
        ${assertTrue "OnePacerr waits for Opnix, ZFS, Jellyfin, and verified admin auth" (builtins.all (unit: builtins.elem unit (containerService.after or [])) ["opnix-secrets.service" "zfs-mount.service" "jellyfin.service" "jellyfin-admin-auth.service"] && builtins.all (unit: builtins.elem unit (containerService.requires or [])) ["opnix-secrets.service" "zfs-mount.service" "jellyfin.service" "jellyfin-admin-auth.service"])}
        ${assertEqual "OnePacerr refuses to start without the media ZFS mount" "/srv/media" (containerServiceUnitConfig.ConditionPathIsMountPoint or null)}
        ${assertEqual "OnePacerr refuses to start without its exact library directory" libraryHostPath (containerServiceUnitConfig.ConditionPathIsDirectory or null)}
        ${assertTrue "OnePacerr requires its media mount" (builtins.elem libraryHostPath (containerServiceUnitConfig.RequiresMountsFor or []))}
        ${assertTrue "OnePacerr has no published ports" ((container.ports or []) == [])}
        ${assertTrue "OnePacerr doesn't use host networking" (!(builtins.elem "host" (container.networks or [])) && !(lib.any (option: lib.hasInfix "--network=host" option) (container.extraOptions or [])))}
        ${assertTrue "OnePacerr runtime env renderer is present" (envScript != null)}
        ${assertTrue "OnePacerr renderer stays outside shared media service script bundles" (!(sharedMediaScripts ? "onepacerr-env.py"))}
        ${assertEqual "Arr apps keep their direct Ultra Transmission integrations" [true true true] (map (app: configuredDrlight.myConfig.mediaManagement.${app}.transmission.enable) ["radarr" "sonarr" "lidarr"])}
        ${assertEqual "Arr apps retain the existing local staging root" [arrStagingRoot arrStagingRoot arrStagingRoot] (map (app: configuredDrlight.myConfig.mediaManagement.${app}.transmission.localPath) ["radarr" "sonarr" "lidarr"])}
        ${assertEqual "Arr apps retain the existing Ultra RPC endpoint file" ["/run/secrets/ultra-media-stage-rpc-url" "/run/secrets/ultra-media-stage-rpc-url" "/run/secrets/ultra-media-stage-rpc-url"] (map (app: configuredDrlight.myConfig.mediaManagement.${app}.transmission.rpcUrlFile) ["radarr" "sonarr" "lidarr"])}
        ${assertEqual "Arr apps retain the existing Ultra download-root file" ["/run/secrets/ultra-media-stage-download-root" "/run/secrets/ultra-media-stage-download-root" "/run/secrets/ultra-media-stage-download-root"] (map (app: configuredDrlight.myConfig.mediaManagement.${app}.transmission.remotePathFile) ["radarr" "sonarr" "lidarr"])}

        ${lib.optionalString (envScript != null) ''
          set -eu
          mkdir -p "$TMPDIR/credentials"
          printf '%s' 'fixture-user' > "$TMPDIR/credentials/username"
          printf '%s' 'fake#pass=word' > "$TMPDIR/credentials/password"
          renderer_output=$(${pkgs.python3}/bin/python ${lib.escapeShellArg (toString envScript)} \
            --username-file "$TMPDIR/credentials/username" \
            --password-file "$TMPDIR/credentials/password" \
            --output "$TMPDIR/credentials.env" 2>"$TMPDIR/renderer.stderr")

          if [ -n "$renderer_output" ] || grep -Eq 'fixture-user|fake#pass=word' "$TMPDIR/renderer.stderr"; then
            echo "FAIL: env renderer disclosed credential contents"
            exit 1
          fi
          if [ "$(stat -c '%a' "$TMPDIR/credentials.env")" != "600" ]; then
            echo "FAIL: env file is not mode 0600"
            exit 1
          fi
          if [ "$(stat -c '%a' "$TMPDIR")" != "700" ]; then
            echo "FAIL: env directory is not mode 0700"
            exit 1
          fi
          grep -Fx 'JELLYFIN_USERNAME=fixture-user' "$TMPDIR/credentials.env" >/dev/null
          grep -Fx 'JELLYFIN_PASSWORD=fake#pass=word' "$TMPDIR/credentials.env" >/dev/null

          printf 'bad\nvalue' > "$TMPDIR/credentials/multiline"
          if ${pkgs.python3}/bin/python ${lib.escapeShellArg (toString envScript)} \
            --username-file "$TMPDIR/credentials/multiline" \
            --password-file "$TMPDIR/credentials/password" \
            --output "$TMPDIR/invalid.env" 2>"$TMPDIR/multiline.stderr"; then
            echo "FAIL: env renderer accepted a multiline secret"
            exit 1
          fi
          if grep -Eq 'bad|value' "$TMPDIR/multiline.stderr"; then
            echo "FAIL: env renderer disclosed rejected secret contents"
            exit 1
          fi
          echo "OnePacerr runtime environment rendering tests passed"
        ''}

        if [ "$failures" -ne 0 ]; then exit 1; fi
        echo "All Drlight OnePacerr tests passed"
        touch "$out"
      '';
in {
  drlightOnePacerrTest =
    if self == null
    then skipped
    else checks;
}
