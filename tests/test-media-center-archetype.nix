# Evaluated behavior tests for the reusable type-media-center archetype and
# drlight's local media-service presentation.
{
  pkgs,
  self ? null,
  inputs ? {},
  ...
}: let
  inherit (pkgs) lib;
  catalog = import ../library/machines/catalog.nix {inherit inputs;};
  observabilityInventory = import ../library/machines/observability-inventory.nix {inherit catalog;};
  typeObservabilitySource = builtins.readFile ../library/archetypes/type-observability.nix;
  drlightMachine = catalog.drlight;
  sshPublicKey = import ../library/ssh-public-key.nix;

  hasModule = suffix: machine:
    lib.any (module: lib.hasSuffix suffix (builtins.toString module)) machine.modules;

  checkEqual = name: expected: actual:
    if expected == actual
    then ''echo "  ${name}: OK"''
    else ''echo ${lib.escapeShellArg "FAIL: ${name}: expected ${builtins.toJSON expected}, got ${builtins.toJSON actual}"}; failures=1'';

  checkTrue = name: condition: checkEqual name true condition;
  checkFalse = name: condition: checkEqual name false condition;

  skipped = name:
    pkgs.runCommand "test-${name}-skipped" {} ''
      echo "Skipped: self not provided"
      touch $out
    '';

  checks =
    if self == null
    then null
    else let
      drlight = self.nixosConfigurations.drlight.config;
      # Re-evaluate the selected media machine without its direct backend
      # archetype. This proves the media-center composition does not itself
      # enable observability services.
      libraryLib = import ../library/lib/mk-system.nix {lib = inputs.nixpkgs.lib;};
      inputsWithSelf = inputs // {inherit self;};
      drlightWithoutObservability =
        (libraryLib.mkNixosSystem {
          inputs = inputsWithSelf;
          inherit (drlightMachine) hostname system extraSpecialArgs overrides;
          modules =
            [
              inputs.disko.nixosModules.disko
              (observabilityInventory.machineModule drlightMachine)
            ]
            ++ lib.filter
            (module: !(lib.hasSuffix "/archetypes/type-observability.nix" (builtins.toString module)))
            drlightMachine.modules;
        }).config;
      homepageServices = drlight.services.homepage-dashboard.services or [];
      homepageHrefs = services:
        lib.concatMap
        (
          section:
            lib.concatMap
            (
              category:
                map (entry: (builtins.head (builtins.attrValues entry)).href) category
            )
            (builtins.attrValues section)
        )
        services;
      sortedHomepageHrefs = builtins.sort builtins.lessThan (homepageHrefs homepageServices);
      mediaCenterOnlyHomepageHrefs =
        builtins.sort builtins.lessThan
        (homepageHrefs (drlightWithoutObservability.services.homepage-dashboard.services or []));
      caddyRoutes = builtins.attrNames (drlight.services.caddy.virtualHosts or {});
      caddyAppConfigs = drlight.myConfig.caddy.apps or {};
      caddyApps = builtins.attrNames caddyAppConfigs;
      expectedCaddyHomepageHrefs = builtins.sort builtins.lessThan (map
        (name: "https://${caddyAppConfigs.${name}.host}")
        (builtins.filter (name: (caddyAppConfigs.${name}.homepage.enable or true)) caddyApps));
      dnsmasqSettings = drlight.services.dnsmasq.settings or {};
      caddyDnsRecords = map (name: "${caddyAppConfigs.${name}.host},100.89.187.92") caddyApps;
      dnsmasqHostRecordLines = builtins.concatStringsSep "\n" (map (record: "host-record=${record}") (dnsmasqSettings.host-record or []));
      drlightWithSyntheticCaddyApp =
        (self.nixosConfigurations.drlight.extendModules {
          modules = [
            {
              myConfig.caddy.apps.synthetic = {
                host = "synthetic.home.buildingbananas.com";
                upstream = "http://127.0.0.1:9999";
                homepage = {
                  title = "Synthetic";
                  group = "Test";
                  description = "Synthetic Caddy application";
                  widgets = [
                    {
                      type = "customapi";
                      url = "http://127.0.0.1:9999/health";
                    }
                  ];
                };
              };
            }
          ];
        }).config;
      syntheticHomepageServices = drlightWithSyntheticCaddyApp.services.homepage-dashboard.services or [];
      syntheticHomepageHrefs = homepageHrefs syntheticHomepageServices;
      homepageServiceEntries =
        lib.concatMap
        (section: lib.concatMap (group: group) (builtins.attrValues section))
        homepageServices;
      syntheticHomepageEntries =
        lib.concatMap
        (section: lib.concatMap (group: group) (builtins.attrValues section))
        syntheticHomepageServices;
      syntheticHomepageEntry = lib.findFirst (entry: entry ? Synthetic) {} syntheticHomepageEntries;
      grafanaHomepageEntry = lib.findFirst (entry: entry ? Grafana) {} homepageServiceEntries;
      grafanaHomepageWidgets = (grafanaHomepageEntry.Grafana or {}).widgets or [];
      grafanaHomepageEnvironment = drlight.systemd.services.homepage-dashboard.environment or {};
      grafanaHomepageCredentials = drlight.systemd.services.homepage-dashboard.serviceConfig.LoadCredential or [];
      syntheticDnsRecords = drlightWithSyntheticCaddyApp.services.dnsmasq.settings.host-record or [];
      resticJobs = drlight.services.restic.backups or {};
      backupPaths = drlight.myConfig.backup.paths or [];
      onePasswordSecrets = drlight.myConfig.onepassword.secrets or {};
      secretValues = builtins.attrValues onePasswordSecrets;
      cacheOnlyDiskConfig = import ../disk-configs/drlight-cache.nix;
      cacheOnlyDisks = cacheOnlyDiskConfig.disko.devices.disk or {};
      cacheDisks = diskoDevices.disk or {};
      cacheDisk = cacheDisks.cache or {};
      cachePartitions = (cacheDisk.content or {}).partitions or {};
      cacheFilesystem = cachePartitions.cache.content or {};
      zfsMountpointService = drlight.systemd.services.zfs-media-mountpoints or {};
      localStorageTmpfiles = drlight.systemd.tmpfiles.rules or [];
      localStorageFilesystem = drlight.fileSystems."/srv/local" or {};
      jellyfinUnitConfig = drlight.systemd.services.jellyfin.unitConfig or {};
      jellyfinService = drlight.systemd.services.jellyfin or {};
      mediaLibraryFoldersService = drlight.systemd.services.media-library-folders or {};
      mediaLibraryFoldersScript = mediaLibraryFoldersService.script or "";
      diskoDevices = (drlight.disko or {}).devices or {};
      diskoDisks = diskoDevices.disk or {};
      diskoDisk = diskoDisks.main or {};
      diskoPartitions = (diskoDisk.content or {}).partitions or {};
      jellyfinMountRequirements = drlight.systemd.services.jellyfin.unitConfig.RequiresMountsFor or [];
      expectedLocalHomepageHrefs = builtins.sort builtins.lessThan [
        "https://grafana.home.buildingbananas.com"
        "https://jellyfin.home.buildingbananas.com"
      ];
      expectedMediaCenterOnlyHomepageHrefs = ["https://jellyfin.home.buildingbananas.com"];
      expectedLocalCaddyRoutes = builtins.sort builtins.lessThan [
        "dashboard.home.buildingbananas.com"
        "grafana.home.buildingbananas.com"
        "jellyfin.home.buildingbananas.com"
      ];
      expectedLocalCaddyApps = builtins.sort builtins.lessThan ["dashboard" "grafana" "jellyfin"];
      expectedLocalCaddyUpstreams = {
        dashboard = "http://127.0.0.1:8082";
        grafana = "http://127.0.0.1:3000";
        jellyfin = "http://127.0.0.1:8096";
      };
      actualLocalCaddyUpstreams = lib.mapAttrs (_: app: app.upstream) (drlight.myConfig.caddy.apps or {});
    in {
      mediaCenterArchetypeTest = pkgs.runCommand "test-media-center-archetype" {} ''
        failures=0
        echo "=== Evaluating type-media-center composition and backend separation ==="

        ${checkTrue "drlight selects type-media-center" (hasModule "/archetypes/type-media-center.nix" drlightMachine)}
        ${checkTrue "drlight selects type-observability separately" (hasModule "/archetypes/type-observability.nix" drlightMachine)}
        ${checkFalse "type-observability does not duplicate the server Prometheus module" (lib.hasInfix "../../modules/nixos/prometheus.nix" typeObservabilitySource)}
        ${checkTrue "media-center retains Vector collector" (drlight.myConfig.vector.enable or false)}
        ${checkTrue "media-center runs Vector" (drlight.services.vector.enable or false)}
        ${checkTrue "media-center retains node_exporter" (drlight.services.prometheus.exporters.node.enable or false)}
        ${checkTrue "drlight routes local collector to localhost" (drlight.myConfig.collector.destinationHostname == "localhost")}
        ${checkTrue "Jellyfin is active on drlight" (drlight.services.jellyfin.enable or false)}
        ${checkTrue "Homepage is active on drlight" (drlight.services.homepage-dashboard.enable or false)}

        ${checkTrue "separate type-observability selection enables Prometheus" (hasModule "/archetypes/type-observability.nix" drlightMachine && drlight.services.prometheus.enable)}
        ${checkTrue "separate type-observability selection enables Loki" (drlight.services.loki.enable or false)}
        ${checkTrue "separate type-observability selection enables Alertmanager" (drlight.services.prometheus.alertmanager.enable or false)}
        ${checkTrue "separate type-observability selection enables Grafana" (drlight.services.grafana.enable or false)}

        ${checkFalse "media-center without direct backend does not enable Prometheus" (drlightWithoutObservability.services.prometheus.enable or false)}
        ${checkFalse "media-center without direct backend does not enable Loki" (drlightWithoutObservability.services.loki.enable or false)}
        ${checkFalse "media-center without direct backend does not enable Alertmanager" (drlightWithoutObservability.services.prometheus.alertmanager.enable or false)}
        ${checkFalse "media-center without direct backend does not enable Grafana" (drlightWithoutObservability.services.grafana.enable or false)}
        ${checkTrue "media-center without direct backend still runs Vector" (drlightWithoutObservability.services.vector.enable or false)}
        ${checkTrue "media-center without direct backend still runs node_exporter" (drlightWithoutObservability.services.prometheus.exporters.node.enable or false)}
        ${checkTrue "media-center without direct backend still enables Jellyfin" (drlightWithoutObservability.services.jellyfin.enable or false)}
        ${checkTrue "media-center without direct backend still enables Homepage" (drlightWithoutObservability.services.homepage-dashboard.enable or false)}
        ${checkEqual "media-center-only Homepage links only to local Jellyfin" expectedMediaCenterOnlyHomepageHrefs mediaCenterOnlyHomepageHrefs}

        if [ "$failures" -ne 0 ]; then exit 1; fi
        echo "All type-media-center composition tests passed"
        touch $out
      '';

      drlightMediaPresentationTest = pkgs.runCommand "test-drlight-media-presentation" {} ''
        failures=0
        echo "=== Evaluating drlight Homepage links and Caddy routes ==="

        ${checkEqual "Homepage allows its Tailscale Serve hostname" "dashboard.home.buildingbananas.com,drlight.uaru-daggertooth.ts.net:8443" (drlight.services.homepage-dashboard.allowedHosts or null)}
        ${checkEqual "Homepage entries are derived from all non-self Caddy apps" expectedCaddyHomepageHrefs sortedHomepageHrefs}
        ${checkTrue "Homepage automatically includes a newly added Caddy app" (builtins.elem "https://synthetic.home.buildingbananas.com" syntheticHomepageHrefs)}
        ${checkEqual "Homepage preserves per-app native widget metadata" [
          {
            type = "customapi";
            url = "http://127.0.0.1:9999/health";
          }
        ] ((syntheticHomepageEntry.Synthetic or {}).widgets or [])}
        ${checkEqual "Grafana uses Homepage's native widget" ["grafana"] (map (widget: widget.type or null) grafanaHomepageWidgets)}
        ${checkEqual "Grafana widget credentials come from systemd credentials" ["%d/grafana-username" "%d/grafana-password"] [grafanaHomepageEnvironment.HOMEPAGE_FILE_GRAFANA_USERNAME or null grafanaHomepageEnvironment.HOMEPAGE_FILE_GRAFANA_PASSWORD or null]}
        ${checkEqual "Homepage loads Grafana credential files through systemd" (builtins.sort builtins.lessThan ["grafana-username:/run/secrets/grafana-username" "grafana-password:/run/secrets/grafana-password"]) (builtins.sort builtins.lessThan grafanaHomepageCredentials)}
        ${checkEqual "Homepage exposes only local Jellyfin and Grafana" expectedLocalHomepageHrefs sortedHomepageHrefs}
        ${checkEqual "Caddy routes only dashboard and local Jellyfin/Grafana" expectedLocalCaddyRoutes (builtins.sort builtins.lessThan caddyRoutes)}
        ${checkEqual "Caddy app configuration only includes dashboard and local Jellyfin/Grafana" expectedLocalCaddyApps (builtins.sort builtins.lessThan caddyApps)}
        ${checkEqual "Caddy proxies only to local Homepage, Grafana, and Jellyfin" expectedLocalCaddyUpstreams actualLocalCaddyUpstreams}

        if [ "$failures" -ne 0 ]; then exit 1; fi
        echo "All drlight media presentation tests passed"
        touch $out
      '';

      drlightRootSshTest = pkgs.runCommand "test-drlight-root-ssh" {} ''
        failures=0
        echo "=== Evaluating drlight root SSH access policy ==="

        ${checkEqual "root SSH uses the approved public key" [sshPublicKey] (drlight.users.users.root.openssh.authorizedKeys.keys or [])}
        ${checkEqual "root SSH is key-only" "prohibit-password" (drlight.services.openssh.settings.PermitRootLogin or null)}
        ${checkFalse "root password authentication remains disabled" (drlight.services.openssh.settings.PasswordAuthentication or false)}

        if [ "$failures" -ne 0 ]; then exit 1; fi
        echo "All drlight root SSH tests passed"
        touch $out
      '';

      drlightMediaStorageTest =
        pkgs.runCommand "test-drlight-media-storage" {
          nativeBuildInputs = [pkgs.dnsmasq pkgs.dnsutils];
        } ''
          failures=0
          echo "=== Evaluating drlight ZFS media storage and Jellyfin mount dependency ==="

          ${checkTrue "existing media pool is imported" (builtins.elem "media" (drlight.boot.zfs.extraPools or []))}
          ${checkTrue "Drlight DNS server is enabled" (drlight.services.dnsmasq.enable or false)}
          ${checkFalse "Drlight DNS server does not replace the machine's local resolver" drlight.services.dnsmasq.resolveLocalQueries}
          ${checkTrue "Drlight DNS server listens on tailscale0" (builtins.elem "tailscale0" (dnsmasqSettings.interface or []))}
          ${checkTrue "Drlight DNS accepts tailnet UDP and TCP queries" (builtins.elem 53 (drlight.networking.firewall.interfaces.tailscale0.allowedUDPPorts or []) && builtins.elem 53 (drlight.networking.firewall.interfaces.tailscale0.allowedTCPPorts or []))}
          ${checkTrue "Drlight DNS maps every Caddy app to its Tailscale IP" (builtins.all (record: builtins.elem record (dnsmasqSettings.host-record or [])) caddyDnsRecords)}
          ${checkTrue "Drlight DNS preserves Zero's Sunshine route" (builtins.elem "sunshine.home.buildingbananas.com,100.71.97.28" (dnsmasqSettings.host-record or []))}
          ${checkTrue "new Caddy apps automatically receive a split-DNS record" (builtins.elem "synthetic.home.buildingbananas.com,100.89.187.92" syntheticDnsRecords)}

          cat > dnsmasq-test.conf <<'EOF'
          port=5353
          listen-address=127.0.0.1
          bind-interfaces
          no-resolv
          no-hosts
          ${dnsmasqHostRecordLines}
          EOF
          ${pkgs.dnsmasq}/bin/dnsmasq --test --conf-file=dnsmasq-test.conf
          ${pkgs.dnsmasq}/bin/dnsmasq --no-daemon --conf-file=dnsmasq-test.conf --log-facility="$TMPDIR/dnsmasq.log" &
          dnsmasq_pid=$!
          trap 'kill "$dnsmasq_pid" 2>/dev/null || true; wait "$dnsmasq_pid" 2>/dev/null || true' EXIT
          sleep 1
          ${
            lib.concatMapStringsSep "\n" (name: ''
              resolved=$(${pkgs.dnsutils}/bin/dig +short @127.0.0.1 -p 5353 ${lib.escapeShellArg name} A)
              if [ "$resolved" != "100.89.187.92" ]; then
                echo "FAIL: DNS resolved ${name} to $resolved instead of Drlight's Tailscale IP"
                exit 1
              fi
            '') ["dashboard.home.buildingbananas.com" "jellyfin.home.buildingbananas.com" "grafana.home.buildingbananas.com"]
          }
          echo "  Homepage Caddy hostnames resolve to Drlight in split DNS: OK"
          ${checkTrue "Drlight keeps scheduled auto-upgrades enabled by default" drlight.system.autoUpgrade.enable}
          ${checkEqual "scheduled upgrades run through the sentinel guard" "nixos-upgrade-scheduled.service" (drlight.systemd.timers.nixos-upgrade.timerConfig.Unit or null)}
          ${checkEqual "disable sentinel skips scheduled upgrades at runtime" "!/var/lib/nixos-upgrade.disabled" (drlight.systemd.services.nixos-upgrade-scheduled.unitConfig.ConditionPathExists or null)}
          ${checkFalse "manual upgrades are not gated by the scheduled sentinel" (drlight.systemd.services.nixos-upgrade.unitConfig ? ConditionPathExists)}
          ${checkEqual "drlight mints Tailscale auth keys through the deployment task" "devenv-oauth" (drlight.myConfig.tailscale.authKeyMode or null)}
          ${checkEqual "drlight uses the approved homelab and media-center tags" ["tag:home-lab" "tag:media-center"] (drlight.myConfig.tailscale.authKeyTags or [])}
          ${checkFalse "drlight does not store a static Tailscale auth key in OpNix" (drlight.myConfig.onepassword.secrets ? tailscaleAuthKey)}
          ${checkTrue "drlight Tailscale service consumes a transient deployment key file" (lib.hasInfix "/run/devenv/tailscale-auth-key" (drlight.systemd.services.tailscale-autoconnect.script or ""))}
          ${checkEqual "drlight keeps the former zero pool owner host ID" "0badc0de" drlight.networking.hostId}
          ${checkFalse "drlight does not force-import the root pool" drlight.boot.zfs.forceImportRoot}
          ${checkFalse "drlight does not force-import all pools" drlight.boot.zfs.forceImportAll}
          ${checkTrue "drlight uses its dedicated Disko layout" (drlightMachine.disko or false)}
          ${checkTrue "drlight selects the dedicated safe disk module" (hasModule "/disk-configs/drlight.nix" drlightMachine)}
           ${checkEqual "drlight Disko declares OS and cache disks" ["cache" "main"] (builtins.attrNames diskoDisks)}
           ${checkEqual "drlight Disko targets the stable Patriot sda identity" "/dev/disk/by-id/ata-Patriot_P210_512GB_P210IICB25030501733" (diskoDisk.device or null)}
           ${checkEqual "drlight Disko targets the dedicated Samsung NVMe by-id" "/dev/disk/by-id/nvme-Samsung_SSD_990_PRO_2TB_S7L9NJ0Y422825N" (cacheDisk.device or null)}
           ${checkEqual "cache-only Disko config cannot reformat the OS disk" ["cache"] (builtins.attrNames cacheOnlyDisks)}
           ${checkEqual "drlight cache disk has one dedicated partition" ["cache"] (builtins.attrNames cachePartitions)}
           ${checkEqual "NVMe cache partition is ext4" "ext4" (cacheFilesystem.format or null)}
           ${checkEqual "NVMe filesystem mounts at /srv/local" "/srv/local" (cacheFilesystem.mountpoint or null)}
           ${checkTrue "NVMe cache mount does not block boot when absent" (builtins.elem "nofail" (cacheFilesystem.mountOptions or []))}
          ${checkEqual "drlight Disko does not define ZFS data-pool devices" [] (builtins.attrNames (diskoDevices.zpool or {}))}
          ${checkEqual "drlight Disko declares ESP, root, and swap partitions" ["ESP" "root" "swap"] (builtins.sort builtins.lessThan (builtins.attrNames diskoPartitions))}
          ${checkEqual "drlight Disko keeps the ESP mounted at /boot" "/boot" (diskoPartitions.ESP.content.mountpoint or null)}
          ${checkTrue "drlight Disko force-formats the EFI filesystem after stale signatures" (lib.hasInfix "mkfs.vfat -F 32" (diskoPartitions.ESP.content.preCreateHook or ""))}
          ${checkEqual "drlight Disko mounts root at /" "/" (diskoPartitions.root.content.mountpoint or null)}
          ${checkEqual "drlight root filesystem is ext4" "ext4" (drlight.fileSystems."/".fsType or null)}
          ${checkEqual "drlight boot filesystem is vfat" "vfat" (drlight.fileSystems."/boot".fsType or null)}
           ${checkFalse "ZFS library path is not shadowed by an fstab mount" (drlight.fileSystems ? "/srv/media")}
           ${checkFalse "ZFS parent path is not in the filesystem table" (drlight.fileSystems ? "/media")}
           ${checkTrue "ZFS parent mountpoint is disabled before automatic mounting" (lib.hasInfix "zfs set mountpoint=none media" (zfsMountpointService.script or "") && builtins.elem "zfs-mount.service" (zfsMountpointService.before or []))}
           ${checkTrue "ZFS library dataset mounts at the sole /srv/media path" (lib.hasInfix "zfs set mountpoint=/srv/media media/library" (zfsMountpointService.script or ""))}
           ${checkTrue "ZFS mountpoint setup waits for the imported media pool" (builtins.elem "zfs-import-media.service" (zfsMountpointService.after or []))}
           ${checkEqual "ZFS pool mounting softly wants mountpoint setup" ["zfs-mount.service"] (zfsMountpointService.wantedBy or [])}
           ${checkTrue "ZFS mountpoint setup runs before Jellyfin" (builtins.elem "jellyfin.service" (zfsMountpointService.before or []))}
           ${checkEqual "Jellyfin requires mountpoint setup to succeed" ["jellyfin.service"] (zfsMountpointService.requiredBy or [])}
           ${checkEqual "NVMe transfer staging directory is prepared" "d /srv/local/cache/ultra 0750 root root - -" (lib.findFirst (rule: lib.hasInfix "/srv/local/cache/ultra" rule) null localStorageTmpfiles)}
           ${checkEqual "NVMe machine-specific state directory is prepared" "d /srv/local/state 0750 root root - -" (lib.findFirst (rule: lib.hasInfix "/srv/local/state" rule) null localStorageTmpfiles)}
           ${checkEqual "NVMe cache mount is ext4" "ext4" (localStorageFilesystem.fsType or null)}
           ${checkTrue "Jellyfin declares its media mount requirement in the unit section" (builtins.elem "/srv/media" jellyfinMountRequirements)}
           ${checkFalse "Jellyfin does not emit RequiresMountsFor in the service section" (jellyfinService.serviceConfig ? RequiresMountsFor)}
           ${checkTrue "Jellyfin starts after ZFS automatic mounts complete" (builtins.elem "zfs-mount.service" (drlight.systemd.services.jellyfin.after or []))}
           ${checkEqual "Jellyfin will not start with the underlying empty directory" "/srv/media" (jellyfinUnitConfig.ConditionPathIsMountPoint or null)}
           ${checkTrue "Nix prepares the five media folders" (builtins.all (path: lib.hasInfix path mediaLibraryFoldersScript) ["/srv/media/audiobooks" "/srv/media/books" "/srv/media/movies" "/srv/media/music" "/srv/media/shows"])}
           ${checkFalse "Nix does not create a Podcasts folder" (lib.hasInfix "/srv/media/podcasts" mediaLibraryFoldersScript)}
           ${checkTrue "Nix prepares media folders after ZFS mount and before Jellyfin" (builtins.elem "zfs-mount.service" (mediaLibraryFoldersService.after or []) && builtins.elem "jellyfin.service" (mediaLibraryFoldersService.before or []) && builtins.elem "media-library-folders.service" (jellyfinService.after or []))}
           ${checkFalse "Jellyfin libraries remain configured through the UI, not an API sync service" (drlight.systemd.services ? jellyfin-declarative-config)}
           ${checkFalse "drlight no longer fetches a Jellyfin admin password for API sync" (onePasswordSecrets ? jellyfinAdminPassword)}

          if [ "$failures" -ne 0 ]; then exit 1; fi
          echo "All drlight media storage tests passed"
          touch $out
        '';

      drlightNoNixarrBackupTest = pkgs.runCommand "test-drlight-no-nixarr-backup" {} ''
        failures=0
        echo "=== Evaluating drlight backup and Nixarr secret absence ==="

        ${checkEqual "drlight has no Restic backup jobs" [] (builtins.attrNames resticJobs)}
        ${checkFalse "backup paths do not include /var/lib/nixarr" (builtins.elem "/var/lib/nixarr" backupPaths)}
        ${checkFalse "drlight Nixarr Restic password secret is absent" (onePasswordSecrets ? drlightResticPassword)}
        ${checkFalse "drlight Nixarr Restic password path is absent" (lib.any (secret: secret.path == "/run/secrets/drlight-restic-password") secretValues)}
        ${checkFalse "drlight Nixarr Restic password reference is absent" (lib.any (secret: secret.reference == "zero-restic/password") secretValues)}

        if [ "$failures" -ne 0 ]; then exit 1; fi
        echo "All drlight backup-removal tests passed"
        touch $out
      '';
    };
in {
  mediaCenterArchetypeTest =
    if checks == null
    then skipped "media-center-archetype"
    else checks.mediaCenterArchetypeTest;
  drlightMediaPresentationTest =
    if checks == null
    then skipped "drlight-media-presentation"
    else checks.drlightMediaPresentationTest;
  drlightMediaStorageTest =
    if checks == null
    then skipped "drlight-media-storage"
    else checks.drlightMediaStorageTest;
  drlightRootSshTest =
    if checks == null
    then skipped "drlight-root-ssh"
    else checks.drlightRootSshTest;
  drlightNoNixarrBackupTest =
    if checks == null
    then skipped "drlight-no-nixarr-backup"
    else checks.drlightNoNixarrBackupTest;
}
