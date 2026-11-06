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
      ultraSyncService = drlight.systemd.services.ultra-media-sync or {};
      ultraSyncServiceConfig = ultraSyncService.serviceConfig or {};
      ultraSyncUnitConfig = ultraSyncService.unitConfig or {};
      ultraSyncCommand = ultraSyncService.script or (ultraSyncServiceConfig.ExecStart or "");
      ultraSyncCommandLines = lib.splitString "\n" ultraSyncCommand;
      ultraSyncTestCommand =
        builtins.replaceStrings
        [
          "/run/secrets/ultra-media-sync-config.json"
          "/run/secrets/ultra-media-sync-key"
          "${pkgs.openssh}/bin/ssh-keygen"
          "${pkgs.openssh}/bin/ssh"
          "${pkgs.rsync}/bin/rsync"
        ]
        [
          "$TMPDIR/fixture-config.json"
          "$TMPDIR/fixture-private-key"
          "$TMPDIR/ultra-sync-test-bin/ssh-keygen"
          "$TMPDIR/ultra-sync-test-bin/ssh"
          "$TMPDIR/ultra-sync-test-bin/rsync"
        ]
        ultraSyncCommand;
      hasUltraSyncJqAssignment = variable: field:
        builtins.any
        (line:
          builtins.match ".*(^|[[:space:]])${variable}=\"[$][(]jq[[:space:]]+-r[[:space:]]+'[.]${field}'[[:space:]]+[^)]*[)]\".*" line != null)
        ultraSyncCommandLines;
      ultraSyncRsyncArguments = let
        commandParts = lib.splitString "rsync " ultraSyncCommand;
      in
        if builtins.length commandParts > 1
        then builtins.elemAt commandParts 1
        else "";
      ultraSyncRsyncOptions =
        builtins.head (lib.splitString " -e " (builtins.head (lib.splitString " --rsh=" ultraSyncRsyncArguments)));
      ultraSyncTimer = drlight.systemd.timers.ultra-media-sync or {};
      ultraSyncTimerConfig = ultraSyncTimer.timerConfig or {};
      ultraSyncConfigSecret = onePasswordSecrets.ultraMediaSyncConfig or {};
      ultraSyncKeySecret = onePasswordSecrets.ultraMediaSyncKey or {};
      opnixSecrets = drlight.services.onepassword-secrets.secrets or {};
      opnixUltraSyncConfigSecret = opnixSecrets.ultraMediaSyncConfig or {};
      opnixUltraSyncKeySecret = opnixSecrets.ultraMediaSyncKey or {};
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
          nativeBuildInputs = [pkgs.dnsmasq pkgs.dnsutils pkgs.jq pkgs.rsync pkgs.fakeroot];
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
           ${checkFalse "NVMe transfer staging directory is not prepared" (lib.any (rule: lib.hasInfix "/srv/local/cache/ultra" rule) localStorageTmpfiles)}
           ${checkEqual "NVMe machine-specific state directory is prepared" "d /srv/local/state 0750 root root - -" (lib.findFirst (rule: lib.hasInfix "/srv/local/state" rule) null localStorageTmpfiles)}
           ${checkEqual "NVMe cache mount is ext4" "ext4" (localStorageFilesystem.fsType or null)}
           ${checkTrue "Jellyfin declares its media mount requirement in the unit section" (builtins.elem "/srv/media" jellyfinMountRequirements)}
           ${checkFalse "Jellyfin does not emit RequiresMountsFor in the service section" (jellyfinService.serviceConfig ? RequiresMountsFor)}
           ${checkTrue "Jellyfin starts after ZFS automatic mounts complete" (builtins.elem "zfs-mount.service" (drlight.systemd.services.jellyfin.after or []))}
           ${checkEqual "Jellyfin will not start with the underlying empty directory" "/srv/media" (jellyfinUnitConfig.ConditionPathIsMountPoint or null)}
           ${checkTrue "Drlight selects the dedicated Ultra media-sync module" (hasModule "/modules/nixos/ultra-media-sync.nix" drlightMachine)}
           ${checkEqual "Ultra media sync is a oneshot service" "oneshot" (ultraSyncServiceConfig.Type or null)}
           ${checkTrue "Ultra media sync runs as its dedicated unprivileged service account" ((ultraSyncServiceConfig.User or null) == "ultra-sync" && (drlight.users.users.ultra-sync.isSystemUser or false))}
           ${checkTrue "Ultra media sync runs in the library-access group" ((ultraSyncServiceConfig.Group or null) == "users")}
           ${checkTrue "Ultra media sync starts after networking and ZFS mounts" (builtins.elem "network-online.target" (ultraSyncService.after or []) && builtins.elem "zfs-mount.service" (ultraSyncService.after or []))}
           ${checkEqual "Ultra media sync requires the media mountpoint" "/srv/media" (ultraSyncUnitConfig.ConditionPathIsMountPoint or null)}
           ${checkTrue "Ultra media sync waits for OpNix secrets" (builtins.elem "opnix-secrets.service" (ultraSyncService.after or []) && builtins.elem "opnix-secrets.service" (ultraSyncService.requires or []))}
           ${checkTrue "Ultra media sync reads its runtime JSON configuration with jq" (lib.hasInfix "/run/secrets/ultra-media-sync-config.json" ultraSyncCommand && lib.hasInfix "jq" ultraSyncCommand)}
           ${checkTrue "Ultra media sync reads its runtime private key" (lib.hasInfix "/run/secrets/ultra-media-sync-key" ultraSyncCommand)}
           ${checkTrue "Ultra media sync builds rsync transfers from runtime configuration" (lib.hasInfix "rsync" ultraSyncCommand && lib.hasInfix "/run/secrets/ultra-media-sync-config.json" ultraSyncCommand)}
           ${checkTrue "Ultra media sync assigns each endpoint variable from jq using its matching selector" (builtins.all (field: hasUltraSyncJqAssignment (builtins.elemAt field 0) (builtins.elemAt field 1)) [["host" "host"] ["username" "username"] ["port" "port"] ["mediaRoot" "mediaRoot"] ["knownHosts" "knownHosts"]])}
           ${checkFalse "Ultra media sync test script does not reset PATH" (lib.hasInfix "PATH=" ultraSyncTestCommand)}
           ${checkFalse "Ultra media sync test script does not retain an absolute SSH executable path" (lib.hasInfix "/bin/ssh" ultraSyncTestCommand)}
           ${checkFalse "Ultra media sync test script does not retain an absolute rsync executable path" (lib.hasInfix "/bin/rsync" ultraSyncTestCommand)}
           if [ -n ${lib.escapeShellArg ultraSyncCommand} ]; then
             mkdir -p "$TMPDIR/ultra-sync-test-bin"
             cat > "$TMPDIR/ultra-sync-test-bin/ssh" <<'EOF'
          #!${pkgs.runtimeShell}
          {
            printf '%s\n' 'SSH_CALL'
            printf '%s\n' "$@"
          } >> "$SSH_CAPTURE"
          remote_command="''${!#}"
          if [[ "$remote_command" == *"-printf"* ]]; then
            printf 'fixture space\\with\ttab\0unconfigured-fixture-folder\0'
          else
            printf '/fixture/remote/media/fixture space\\with\ttab\0/fixture/remote/media/unconfigured-fixture-folder\0'
          fi
          EOF
             cat > "$TMPDIR/ultra-sync-test-bin/rsync" <<'EOF'
          #!${pkgs.runtimeShell}
          {
            printf '%s\n' 'RSYNC_CALL'
            printf '%s\n' "$@"
          } >> "$RSYNC_CAPTURE"
          for argument in "$@"; do
            case "$argument" in
              *UserKnownHostsFile=*)
                known_hosts_path=''${argument#*UserKnownHostsFile=}
                known_hosts_path=''${known_hosts_path%% *}
                printf '%s\n' "$known_hosts_path" > "$KNOWN_HOSTS_PATH_CAPTURE"
                cat "$known_hosts_path" > "$KNOWN_HOSTS_CAPTURE"
                ;;
            esac
          done
          EOF
             ln -s ${pkgs.openssh}/bin/ssh-keygen "$TMPDIR/ultra-sync-test-bin/ssh-keygen"
             chmod +x "$TMPDIR/ultra-sync-test-bin/ssh" "$TMPDIR/ultra-sync-test-bin/rsync"
             cat > "$TMPDIR/fixture-config.json" <<'EOF'
          {"host":"example.invalid","username":"fixture-user","port":22222,"mediaRoot":"/fixture/remote/media","knownHosts":"[example.invalid]:22222 ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFixtureOnlySyntheticKeyMaterial000000000000000000000000000000000000","mappings":[{"source":"fixture space\\with\ttab","destination":"movies"}]}
          EOF
             printf '%s\n' 'fixture-only-private-key' > "$TMPDIR/fixture-private-key"
             : > "$TMPDIR/rsync-arguments"
             : > "$TMPDIR/ssh-arguments"
             : > "$TMPDIR/known-hosts-content"
             : > "$TMPDIR/known-hosts-path"
             export RSYNC_CAPTURE="$TMPDIR/rsync-arguments"
             export SSH_CAPTURE="$TMPDIR/ssh-arguments"
             export KNOWN_HOSTS_CAPTURE="$TMPDIR/known-hosts-content"
             export KNOWN_HOSTS_PATH_CAPTURE="$TMPDIR/known-hosts-path"
             export PATH="$TMPDIR/ultra-sync-test-bin:$PATH"
             printf '%s\n' ${lib.escapeShellArg ultraSyncTestCommand} > "$TMPDIR/ultra-media-sync-test.sh"
             if ! ${pkgs.bash}/bin/bash "$TMPDIR/ultra-media-sync-test.sh" > "$TMPDIR/service-output"; then
               echo "FAIL: Ultra media sync executes with synthetic fixture configuration"
               failures=1
             fi
             expected_remote_source=$(printf 'fixture-user@example.invalid:/fixture/remote/media/fixture space\\with\ttab/')
             if grep -Fxq "$expected_remote_source" "$TMPDIR/rsync-arguments"; then
               echo "  Ultra media sync passes the fixture remote source to rsync: OK"
             else
               echo "FAIL: Ultra media sync passes the fixture remote source to rsync"
               failures=1
             fi
             if grep -Eq '^/srv/media/movies/?$' "$TMPDIR/rsync-arguments"; then
               echo "  Ultra media sync passes the fixture local destination to rsync: OK"
             else
               echo "FAIL: Ultra media sync passes the fixture local destination to rsync"
               failures=1
             fi
             if grep -Eq '(^|[[:space:]])-p([[:space:]]|$)|(^|[[:space:]])-p22222([[:space:]]|$)' "$TMPDIR/rsync-arguments" && grep -Fq '22222' "$TMPDIR/rsync-arguments"; then
               echo "  Ultra media sync passes the fixture SSH port to rsync: OK"
             else
               echo "FAIL: Ultra media sync passes the fixture SSH port to rsync"
               failures=1
             fi
             known_hosts_path=$(sed -n 's/.*UserKnownHostsFile=\([^ ]*\).*/\1/p' "$TMPDIR/rsync-arguments" | head -n 1)
             if [ -n "$known_hosts_path" ] && [ "$known_hosts_path" = "$(cat "$TMPDIR/known-hosts-path")" ] && [ "$known_hosts_path" != "$TMPDIR/fixture-known-hosts" ] && grep -Fxq '[example.invalid]:22222 ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFixtureOnlySyntheticKeyMaterial000000000000000000000000000000000000' "$TMPDIR/known-hosts-content"; then
               echo "  Ultra media sync writes the synthetic known-hosts line to its SSH file: OK"
             else
               echo "FAIL: Ultra media sync writes the synthetic known-hosts line to its SSH file"
               failures=1
             fi
             if grep -Fq 'SSH_CALL' "$TMPDIR/ssh-arguments"; then
               echo "  Ultra media sync enumerates remote source folders through fake SSH: OK"
             else
               echo "FAIL: Ultra media sync enumerates remote source folders through fake SSH"
               failures=1
             fi
             if ! grep -Eq 'Unconfigured remote media folder: .*fixture space' "$TMPDIR/service-output"; then
               echo "  Ultra media sync does not warn for a configured remote folder: OK"
             else
               echo "FAIL: Ultra media sync warns for a configured remote folder"
               failures=1
             fi
             if grep -Fxq 'Unconfigured remote media folder: unconfigured-fixture-folder' "$TMPDIR/service-output"; then
               echo "  Ultra media sync journals unmatched remote folders: OK"
             else
               echo "FAIL: Ultra media sync journals unmatched remote folders"
               failures=1
             fi
             if ! grep -Fq 'unconfigured-fixture-folder' "$TMPDIR/rsync-arguments"; then
               echo "  Ultra media sync never transfers an unmatched remote folder: OK"
             else
               echo "FAIL: Ultra media sync transfers an unmatched remote folder"
               failures=1
             fi
             if ${pkgs.openssh}/bin/ssh-keygen -F '[example.invalid]:22222' -f "$TMPDIR/known-hosts-content" >/dev/null; then
               echo "  Ultra media sync runtime known-hosts file matches the non-default-port alias: OK"
             else
               echo "FAIL: Ultra media sync runtime known-hosts file does not match the non-default-port alias"
               failures=1
             fi
             : > "$TMPDIR/ssh-arguments"
             : > "$TMPDIR/rsync-arguments"
             cat > "$TMPDIR/fixture-config.json" <<'EOF'
          {"host":"example.invalid","username":"fixture-user","port":22222,"mediaRoot":"/fixture/remote/media","knownHosts":"example.invalid ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFixtureOnlySyntheticKeyMaterial000000000000000000000000000000000000","mappings":[{"source":"fixture-folder","destination":"movies"}]}
          EOF
             if ${pkgs.bash}/bin/bash "$TMPDIR/ultra-media-sync-test.sh" > "$TMPDIR/unpinned-output" 2>&1; then
               echo "FAIL: Ultra media sync accepts a pinned host key under the wrong port alias"
               failures=1
             else
               echo "  Ultra media sync rejects a missing non-default-port host-key alias: OK"
             fi
             if [ ! -s "$TMPDIR/ssh-arguments" ]; then
               echo "  Ultra media sync validates host keys before invoking SSH: OK"
             else
               echo "FAIL: Ultra media sync invokes SSH before validating the host-key alias"
               failures=1
             fi
             : > "$TMPDIR/rsync-arguments"
             cat > "$TMPDIR/fixture-config.json" <<'EOF'
          {"host":"example.invalid","username":"fixture-user","port":22222,"mediaRoot":"/fixture/remote/media","knownHosts":"[example.invalid]:22222 ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFixtureOnlySyntheticKeyMaterial000000000000000000000000000000000000","mappings":[{"source":"bad\u0000mapping","destination":"movies"}]}
          EOF
             if ${pkgs.bash}/bin/bash "$TMPDIR/ultra-media-sync-test.sh" > "$TMPDIR/malformed-output" 2>&1; then
               echo "FAIL: Ultra media sync accepts a NUL-containing mapping"
               failures=1
             else
               echo "  Ultra media sync fails on a NUL-containing mapping: OK"
             fi
             if [ ! -s "$TMPDIR/rsync-arguments" ]; then
               echo "  Ultra media sync does not invoke rsync for a malformed mapping: OK"
             else
               echo "FAIL: Ultra media sync invokes rsync for a malformed mapping"
               failures=1
             fi
           else
             echo "FAIL: Ultra media sync has a service script for behavioral execution"
             failures=1
           fi
           ${checkTrue "Ultra media sync uses the runtime port and known-hosts path" (builtins.match ".*[$][{]?port[}]?.*" ultraSyncCommand != null && builtins.match ".*[$][{]?knownHosts[}]?.*" ultraSyncCommand != null)}
           ${checkTrue "Ultra media sync caps bandwidth at 20,000 KiB/s" (lib.hasInfix "--bwlimit=20000" ultraSyncCommand)}
           ${checkTrue "Ultra media sync uses the hidden partial directory" (lib.hasInfix "--partial-dir=.rsync-partial" ultraSyncCommand)}
           ${checkTrue "Ultra media sync protects remote paths with spaces" (lib.hasInfix "--protect-args" ultraSyncCommand)}
           ${checkTrue "Ultra media sync itemizes journal output" (lib.hasInfix "--itemize-changes" ultraSyncCommand && lib.hasInfix "--out-format=" ultraSyncCommand)}
           ${checkTrue "Ultra media sync uses batch SSH" (lib.hasInfix "BatchMode=yes" ultraSyncCommand)}
           ${checkEqual "Ultra media sync uses a group-friendly umask" "0002" (ultraSyncServiceConfig.UMask or null)}
           ${checkFalse "Ultra media sync is not restarted during a NixOS switch" (ultraSyncService.restartIfChanged or true)}
           ${checkTrue "Ultra media sync delays publishing transferred files" (lib.hasInfix "--delay-updates" ultraSyncCommand)}
           ${checkTrue "Ultra media sync enforces strict SSH host-key checking" (lib.hasInfix "StrictHostKeyChecking=yes" ultraSyncCommand && lib.hasInfix "UserKnownHostsFile" ultraSyncCommand)}
           ${checkTrue "Ultra media sync uses basename-only remote folder enumeration" (lib.hasInfix "-printf '%f\\\\0'" ultraSyncCommand)}
           ${checkTrue "Ultra media sync checks jq mapping output before reading it" (lib.hasInfix "mapping_file" ultraSyncCommand && lib.hasInfix "jq --raw-output0" ultraSyncCommand)}
           ${checkFalse "Ultra media sync does not delete destination files" (lib.hasInfix "--delete" ultraSyncCommand)}
           ${checkFalse "Ultra media sync does not remove source files" (lib.hasInfix "--remove-source-files" ultraSyncCommand)}
           ${checkFalse "Ultra media sync does not preserve seedbox owners or raw permissions" (lib.hasInfix "--owner" ultraSyncCommand || lib.hasInfix "--group" ultraSyncCommand || (lib.hasInfix "--perms" ultraSyncCommand && !(lib.hasInfix "--chmod=Du=rwx,Dg=rwx,Do=rx,Fu=rw,Fg=rw,Fo=r,ugo-s,o-t" ultraSyncCommand)) || lib.hasInfix "--archive" ultraSyncCommand || lib.hasInfix "--numeric-ids" ultraSyncCommand || lib.hasInfix "--chown" ultraSyncCommand || builtins.match ".*(^|[[:space:]])-[[:alpha:]]*[aogp][[:alpha:]]*([[:space:]]|$).*" ultraSyncRsyncOptions != null)}
           ${checkTrue "Ultra media sync normalizes copied permissions and clears set-ID/sticky bits" (lib.hasInfix "--chmod=Du=rwx,Dg=rwx,Do=rx,Fu=rw,Fg=rw,Fo=r,ugo-s,o-t" ultraSyncCommand)}
           ${checkTrue "Ultra media sync preserves file timestamps but omits directory timestamps" (lib.hasInfix "--times" ultraSyncCommand && lib.hasInfix "--omit-dir-times" ultraSyncCommand)}
           ${checkTrue "Ultra media sync validates the pinned host-key alias before SSH use" (lib.hasInfix "ssh-keygen -F" ultraSyncCommand)}
           ${checkEqual "Ultra media sync runs on the hourly schedule" "hourly" (ultraSyncTimerConfig.OnCalendar or null)}
           ${checkFalse "Ultra media sync timer does not launch a catch-up run during a switch" (ultraSyncTimerConfig.Persistent or false)}
           ${checkEqual "Ultra media sync timer activates its service" "ultra-media-sync.service" (ultraSyncTimerConfig.Unit or null)}
           ${checkTrue "Ultra media sync timer is enabled through timers.target" (builtins.elem "timers.target" (ultraSyncTimer.wantedBy or []))}
           ${checkEqual "Drlight resolves unqualified OpNix references through Homelab" "Homelab" (drlight.myConfig.onepassword.defaultVault or null)}
           ${checkEqual "Ultra media sync JSON config secret has its runtime path" "/run/secrets/ultra-media-sync-config.json" (ultraSyncConfigSecret.path or null)}
           ${checkEqual "Ultra media sync private key secret has its runtime path" "/run/secrets/ultra-media-sync-key" (ultraSyncKeySecret.path or null)}
           ${checkTrue "Ultra media sync config secret is restricted to its service account" ((ultraSyncConfigSecret.owner or null) == "ultra-sync" && (ultraSyncConfigSecret.group or null) == "users" && (ultraSyncConfigSecret.mode or null) == "0400")}
           ${checkTrue "Ultra media sync key secret is restricted to its service account" ((ultraSyncKeySecret.owner or null) == "ultra-sync" && (ultraSyncKeySecret.group or null) == "users" && (ultraSyncKeySecret.mode or null) == "0400")}
           ${checkTrue "OpNix materializes the config secret with service ownership and mode" ((opnixUltraSyncConfigSecret.path or null) == "/run/secrets/ultra-media-sync-config.json" && (opnixUltraSyncConfigSecret.owner or null) == "ultra-sync" && (opnixUltraSyncConfigSecret.group or null) == "users" && (opnixUltraSyncConfigSecret.mode or null) == "0400")}
           ${checkTrue "OpNix materializes the key secret with service ownership and mode" ((opnixUltraSyncKeySecret.path or null) == "/run/secrets/ultra-media-sync-key" && (opnixUltraSyncKeySecret.owner or null) == "ultra-sync" && (opnixUltraSyncKeySecret.group or null) == "users" && (opnixUltraSyncKeySecret.mode or null) == "0400")}
           ${checkTrue "Ultra media sync config reference is unqualified and resolved through Homelab" ((ultraSyncConfigSecret.reference or "") != "" && !(lib.hasPrefix "op://" (ultraSyncConfigSecret.reference or "")) && !(lib.hasPrefix "Homelab/" (ultraSyncConfigSecret.reference or "")) && (opnixUltraSyncConfigSecret.reference or null) == "op://Homelab/${ultraSyncConfigSecret.reference or ""}")}
           ${checkTrue "Ultra media sync key reference is unqualified and resolved through Homelab" ((ultraSyncKeySecret.reference or "") != "" && !(lib.hasPrefix "op://" (ultraSyncKeySecret.reference or "")) && !(lib.hasPrefix "Homelab/" (ultraSyncKeySecret.reference or "")) && (opnixUltraSyncKeySecret.reference or null) == "op://Homelab/${ultraSyncKeySecret.reference or ""}")}
           ${checkTrue "Nix prepares the six media folders including comics" (builtins.all (path: lib.hasInfix path mediaLibraryFoldersScript) ["/srv/media/audiobooks" "/srv/media/books" "/srv/media/comics" "/srv/media/movies" "/srv/media/music" "/srv/media/shows"])}
           ${checkFalse "Nix does not create a Podcasts folder" (lib.hasInfix "/srv/media/podcasts" mediaLibraryFoldersScript)}
           ${checkTrue "Nix prepares media folders after ZFS mount and before Jellyfin" (builtins.elem "zfs-mount.service" (mediaLibraryFoldersService.after or []) && builtins.elem "jellyfin.service" (mediaLibraryFoldersService.before or []) && builtins.elem "media-library-folders.service" (jellyfinService.after or []))}
           ${checkFalse "Jellyfin libraries remain configured through the UI, not an API sync service" (drlight.systemd.services ? jellyfin-declarative-config)}
           ${checkFalse "drlight no longer fetches a Jellyfin admin password for API sync" (onePasswordSecrets ? jellyfinAdminPassword)}

           if ${pkgs.fakeroot}/bin/fakeroot ${pkgs.bash}/bin/bash <<'EOF'
          set -e
          mkdir -p "$TMPDIR/restrictive-source/library" "$TMPDIR/normalized-destination"
          printf 'fixture media bytes\n' > "$TMPDIR/restrictive-source/library/movie.mkv"
          chmod 2700 "$TMPDIR/restrictive-source/library"
          chmod 4700 "$TMPDIR/restrictive-source/library/movie.mkv"
          touch -d @1000000000 "$TMPDIR/restrictive-source/library/movie.mkv"
          touch -d @1000000000 "$TMPDIR/restrictive-source/library"
          ${pkgs.rsync}/bin/rsync --recursive --times --omit-dir-times --perms --chmod=Du=rwx,Dg=rwx,Do=rx,Fu=rw,Fg=rw,Fo=r,ugo-s,o-t "$TMPDIR/restrictive-source/" "$TMPDIR/normalized-destination/"
          copied_dir_mode=$(stat -c '%a' "$TMPDIR/normalized-destination/library")
          copied_file_mode=$(stat -c '%a' "$TMPDIR/normalized-destination/library/movie.mkv")
          source_dir_mtime=$(stat -c '%Y' "$TMPDIR/restrictive-source/library")
          copied_dir_mtime=$(stat -c '%Y' "$TMPDIR/normalized-destination/library")
          source_file_mtime=$(stat -c '%Y' "$TMPDIR/restrictive-source/library/movie.mkv")
          copied_file_mtime=$(stat -c '%Y' "$TMPDIR/normalized-destination/library/movie.mkv")
          if [ "$copied_dir_mode" = 775 ] && [ "$copied_file_mode" = 664 ]; then
            echo "  Real rsync normalizes restrictive/set-ID source modes to 775/664: OK"
          else
            echo "FAIL: Real rsync produced directory/file modes $copied_dir_mode/$copied_file_mode instead of 775/664"
            exit 1
          fi
          if [ "$copied_file_mtime" = "$source_file_mtime" ]; then
            echo "  Real rsync preserves the source file mtime: OK"
          else
            echo "FAIL: Real rsync produced file mtime $copied_file_mtime instead of source mtime $source_file_mtime"
            exit 1
          fi
          if [ "$copied_dir_mtime" != "$source_dir_mtime" ]; then
            echo "  Real rsync omits the source directory mtime: OK"
          else
            echo "FAIL: Real rsync copied source directory mtime $source_dir_mtime"
            exit 1
          fi
          EOF
           then
             :
           else
             failures=1
           fi

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
