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
    lib.any (module: (builtins.isPath module || builtins.isString module) && lib.hasSuffix suffix (builtins.toString module)) machine.modules;

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
      drlightWithDownloadStageEnabled =
        (self.nixosConfigurations.drlight.extendModules {
          modules = [{myConfig.ultraMediaDownloadStage.enable = true;}];
        }).config;
      drlightWithRadarrAuthOnly =
        (self.nixosConfigurations.drlight.extendModules {
          modules = [{myConfig.mediaManagement.radarr.transmission.enable = lib.mkForce false;}];
        }).config;
      drlightWithMylarSettingsManagementDisabled =
        (self.nixosConfigurations.drlight.extendModules {
          modules = [{services.mylar3.manageSettingsFile = false;}];
        }).config;
      arrReconcileConfigPath = machine: app:
        lib.last (lib.splitString "--config " (machine.systemd.services.${app + "-media-config-sync"}.serviceConfig.ExecStart or ""));
      ultraDownloadStageEnabledTimer = drlightWithDownloadStageEnabled.systemd.timers.ultra-media-download-stage or {};
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
      ultraSyncStagingSource = builtins.readFile ../modules/nixos/scripts/ultra-media-download-stage.py;
      ultraSyncPolicySource = builtins.readFile ../modules/nixos/scripts/ultra-media-cleanup.py;
      ultraSyncCleanupModuleSource = builtins.readFile ../modules/nixos/ultra-media-cleanup.nix;
      ultraDownloadStageService = drlight.systemd.services.ultra-media-download-stage or {};
      ultraDownloadStageServiceConfig = ultraDownloadStageService.serviceConfig or {};
      ultraDownloadStageCommand = ultraDownloadStageService.script or (ultraDownloadStageServiceConfig.ExecStart or "");
      ultraCleanupService = drlight.systemd.services.ultra-media-cleanup or {};
      ultraCleanupServiceConfig = ultraCleanupService.serviceConfig or {};
      ultraCleanupCommand = ultraCleanupService.script or (ultraCleanupServiceConfig.ExecStart or "");
      ultraCleanupTimer = drlight.systemd.timers.ultra-media-cleanup or {};
      ultraDownloadStageTimer = drlight.systemd.timers.ultra-media-download-stage or {};
      ultraDownloadStageTimerConfig = ultraDownloadStageTimer.timerConfig or {};
      ultraDownloadStageEnabled = drlight.myConfig.ultraMediaDownloadStage.enable or false;
      ultraStageSecretNames = [
        "ultraMediaStageHost"
        "ultraMediaStageUsername"
        "ultraMediaStageKnownHosts"
        "ultraMediaStageKey"
        "ultraMediaStageRpcUrl"
        "ultraMediaStageDownloadRoot"
        "ultraMediaStageRpcUsername"
        "ultraMediaStageRpcPassword"
      ];
      ultraStageSecrets = map (name: onePasswordSecrets.${name} or {}) ultraStageSecretNames;
      ultraStagePrivateSecretNames = [
        "ultraMediaStageHost"
        "ultraMediaStageUsername"
        "ultraMediaStageKnownHosts"
        "ultraMediaStageKey"
      ];
      ultraStageSharedSecretNames = [
        "ultraMediaStageRpcUrl"
        "ultraMediaStageDownloadRoot"
        "ultraMediaStageRpcUsername"
        "ultraMediaStageRpcPassword"
      ];
      ultraStagePrivateSecrets = map (name: onePasswordSecrets.${name} or {}) ultraStagePrivateSecretNames;
      ultraStageSharedSecrets = map (name: onePasswordSecrets.${name} or {}) ultraStageSharedSecretNames;
      ultraStageExpectedReferences = [
        "Ultra Media Sync Config/host"
        "Ultra Media Sync Config/username"
        "Ultra Media Sync Config/knownHosts"
        "Ultra Media Sync Key/private key"
        "Ultra Media Sync Config/rpcUrl"
        "Ultra Media Sync Config/completedDownloadsRoot"
        "Ultra - Transmission/username"
        "Ultra - Transmission/password"
      ];
      ultraStageKeySecret = onePasswordSecrets.ultraMediaStageKey or {};
      ultraStageRpcUsernameSecret = onePasswordSecrets.ultraMediaStageRpcUsername or {};
      ultraStageRpcPasswordSecret = onePasswordSecrets.ultraMediaStageRpcPassword or {};
      opnixSecrets = drlight.services.onepassword-secrets.secrets or {};
      opnixUltraStagePrivateSecrets = map (name: opnixSecrets.${name} or {}) ultraStagePrivateSecretNames;
      opnixUltraStageSharedSecrets = map (name: opnixSecrets.${name} or {}) ultraStageSharedSecretNames;
      opnixUltraStageKeySecret = opnixSecrets.ultraMediaStageKey or {};
      opnixUltraStageRpcUsernameSecret = opnixSecrets.ultraMediaStageRpcUsername or {};
      opnixUltraStageRpcPasswordSecret = opnixSecrets.ultraMediaStageRpcPassword or {};
      mediaAuthSecretNames = [
        "radarrAdminUsername"
        "radarrAdminPassword"
        "sonarrAdminUsername"
        "sonarrAdminPassword"
        "lidarrAdminUsername"
        "lidarrAdminPassword"
        "bazarrAdminUsername"
        "bazarrAdminPassword"
        "mylar3AdminUsername"
        "mylar3AdminPassword"
        "jellyfinAdminUsername"
        "jellyfinAdminPassword"
      ];
      mediaAuthExpectedReferences = [
        "Radarr/username"
        "Radarr/password"
        "Sonarr/username"
        "Sonarr/password"
        "Lidarr/username"
        "Lidarr/password"
        "Bazaar/username"
        "Bazaar/password"
        "Mylar3/username"
        "Mylar3/password"
        "Jellyfin/username"
        "Jellyfin/password"
      ];
      mediaAuthSecrets = map (name: onePasswordSecrets.${name} or {}) mediaAuthSecretNames;
      opnixMediaAuthSecrets = map (name: opnixSecrets.${name} or {}) mediaAuthSecretNames;
      mediaAuthApps = [
        {
          name = "radarr";
          sync = "radarr-media-config-sync";
        }
        {
          name = "sonarr";
          sync = "sonarr-media-config-sync";
        }
        {
          name = "lidarr";
          sync = "lidarr-media-config-sync";
        }
        {
          name = "bazarr";
          sync = "bazarr-media-config-sync";
        }
        {
          name = "mylar3";
          sync = "mylar3";
        }
        {
          name = "jellyfin";
          sync = "jellyfin-admin-auth";
        }
      ];
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
      expectedMediaManagerHomepageHrefs = builtins.sort builtins.lessThan (map
        (app: "http://drlight.uaru-daggertooth.ts.net:${toString app.port}")
        mediaManagementApps);
      expectedLocalHomepageHrefs = builtins.sort builtins.lessThan (
        [
          "https://grafana.home.buildingbananas.com"
          "https://jellyfin.home.buildingbananas.com"
        ]
        ++ expectedMediaManagerHomepageHrefs
      );
      expectedMediaCenterOnlyHomepageHrefs = builtins.sort builtins.lessThan (
        ["https://jellyfin.home.buildingbananas.com"]
        ++ expectedMediaManagerHomepageHrefs
      );
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
      mediaManagementApps = [
        {
          name = "radarr";
          root = "/srv/media/movies";
          port = 7878;
        }
        {
          name = "sonarr";
          root = "/srv/media/shows";
          port = 8989;
        }
        {
          name = "lidarr";
          root = "/srv/media/music";
          port = 8686;
        }
        {
          name = "mylar3";
          root = "/srv/media/comics";
          port = 8090;
        }
        {
          name = "bazarr";
          root = "/srv/media/movies";
          port = 6767;
        }
      ];
      mediaManagementService = name: drlight.systemd.services.${name} or {};
      mediaManagementServiceConfig = name: (mediaManagementService name).serviceConfig or {};
      mediaManagementRootService = drlight.systemd.services.media-management-roots or {};
      preparedJellyfinLibraryRoots = map (name: "/srv/media/${name}") [
        "audiobooks"
        "books"
        "comics"
        "movies"
        "music"
        "shows"
      ];
      preparedArrLibraryRoots = map (app: app.root) mediaManagementApps;
      mylar3Package = drlight.services.mylar3.package;
      mediaManagementRootScript = mediaManagementRootService.script or "";
      mediaManagerDataDirs = [
        {
          name = "radarr";
          path = drlight.services.radarr.dataDir;
        }
        {
          name = "sonarr";
          path = drlight.services.sonarr.dataDir;
        }
        {
          name = "lidarr";
          path = drlight.services.lidarr.dataDir;
        }
        {
          name = "bazarr";
          path = drlight.services.bazarr.dataDir;
        }
      ];
      nonTailnetInterfacePorts = lib.concatLists (lib.mapAttrsToList
        (name: interface:
          if name == "tailscale0"
          then []
          else (interface.allowedTCPPorts or []))
        (drlight.networking.firewall.interfaces or {}));
      mediaManagementServicesReachableOverTailscale =
        builtins.all (app: builtins.elem app.port (drlight.networking.firewall.interfaces.tailscale0.allowedTCPPorts or [])) mediaManagementApps;
      mediaManagementServicesNotGlobal =
        builtins.all (app: !(builtins.elem app.port (drlight.networking.firewall.allowedTCPPorts or []))) mediaManagementApps;
      mediaManagementServicesNotReachableOnOtherInterfaces =
        builtins.all (app: !(builtins.elem app.port nonTailnetInterfacePorts)) mediaManagementApps;
      nonDrlightMachines = builtins.removeAttrs (self.nixosConfigurations or {}) ["drlight"];
      nonDrlightHasNoMediaManagers =
        lib.all
        (machine:
          !(machine.config.services.radarr.enable or false)
          && !(machine.config.services.sonarr.enable or false)
          && !(machine.config.services.lidarr.enable or false)
          && !(machine.config.services.mylar3.enable or false)
          && !(machine.config.services.bazarr.enable or false))
        (builtins.attrValues nonDrlightMachines);
    in {
      drlightMediaManagementTest = pkgs.runCommand "test-drlight-media-management" {nativeBuildInputs = [pkgs.jq];} ''
        failures=0
        echo "=== Evaluating Drlight media-manager ownership, permissions, and network policy ==="
        if ${pkgs.jq}/bin/jq -e '.application == "lidarr" and (.baseUrl | endswith("/api/v1")) and .auth.username.secret == "/run/secrets/lidarr-admin-username" and .auth.password.secret == "/run/secrets/lidarr-admin-password"' ${lib.escapeShellArg (arrReconcileConfigPath drlight "lidarr")} >/dev/null; then
          echo "  Lidarr runtime config identifies the app and uses its v1 URL and Opnix file references: OK"
        else
          echo "FAIL: Lidarr runtime config is missing app identification, its v1 API version, or login secret file references"
          failures=1
        fi
        if ${pkgs.jq}/bin/jq -e '.auth.username.secret == "/run/secrets/radarr-admin-username" and .auth.password.secret == "/run/secrets/radarr-admin-password" and .transmission == {}' ${lib.escapeShellArg (arrReconcileConfigPath drlightWithRadarrAuthOnly "radarr")} >/dev/null; then
          echo "  auth-only Arr config contains no Transmission settings: OK"
        else
          echo "FAIL: auth-only Arr config contains missing credentials or unnecessary Transmission settings"
          failures=1
        fi

        ${checkTrue "Drlight selects the media-management module" (hasModule "/modules/nixos/media-management.nix" drlightMachine)}
        ${lib.concatMapStringsSep "\n" (app: ''
            ${checkTrue "${app.name} is enabled on Drlight" (drlight.services.${app.name}.enable or false)}
            ${checkTrue "${app.name} runs in the shared media group" ((mediaManagementServiceConfig "${app.name}").Group or null == "users")}
            ${checkEqual "${app.name} uses a group-writable umask" "0002" (mediaManagementServiceConfig "${app.name}").UMask or null}
            ${checkTrue "${app.name} has isolated writable temporary storage under strict filesystem protection" (builtins.elem ((mediaManagementServiceConfig "${app.name}").PrivateTmp or false) [true "disconnected"])}
            ${checkEqual "${app.name} uses strict filesystem protection" "strict" ((mediaManagementServiceConfig "${app.name}").ProtectSystem or null)}
            ${checkTrue "${app.name} is granted access to its local media root" (builtins.elem "${app.root}" ((mediaManagementServiceConfig "${app.name}").ReadWritePaths or []))}
            ${checkTrue "${app.name} waits for the local media mount" (builtins.elem "/srv/media" ((mediaManagementService "${app.name}").unitConfig.RequiresMountsFor or []))}
            ${checkTrue "${app.name} can write to the local Arr staging root" (builtins.elem "/srv/media/.arr-staging" ((mediaManagementServiceConfig "${app.name}").ReadWritePaths or []))}
            ${checkTrue "${app.name} starts after shared media roots are prepared" (builtins.elem "media-management-roots.service" ((mediaManagementService "${app.name}").after or []))}
            ${checkTrue "${app.name} requires shared media roots to be prepared" (builtins.elem "media-management-roots.service" ((mediaManagementService "${app.name}").requires or []))}
            ${checkTrue "${app.name} has a service account in the shared media group" ((drlight.users.users.${app.name}.group or null) == "users")}
            ${checkTrue "${app.name} library roots are prepared locally" (lib.hasInfix "${app.root}" mediaLibraryFoldersScript)}
          '')
          mediaManagementApps}
        ${checkTrue "the local Arr staging root is group-writable" (lib.hasInfix "-g users -m 2775 /srv/media/.arr-staging" mediaManagementRootScript)}
        ${checkTrue "Arr state directories are prepared before their service namespaces are created" (builtins.all (app: lib.hasInfix "install -d -o ${app.name} -g users -m 0750 ${app.path}" mediaManagementRootScript && builtins.elem "${app.name}.service" (mediaManagementRootService.before or [])) mediaManagerDataDirs)}
        ${checkTrue "media-library roots preserve group-writable permissions" (lib.hasInfix "-g users -m 2775" mediaLibraryFoldersScript)}
        ${checkFalse "Arr staging is excluded from all prepared Jellyfin and Arr library roots" (
          lib.hasInfix "/srv/media/.arr-staging" mediaLibraryFoldersScript
          || builtins.elem "/srv/media/.arr-staging" preparedJellyfinLibraryRoots
          || builtins.elem "/srv/media/.arr-staging" preparedArrLibraryRoots
        )}
        ${checkTrue "Bazarr can read and write the Drlight-local Sonarr library root" (builtins.elem "/srv/media/shows" ((mediaManagementServiceConfig "bazarr").ReadWritePaths or []))}
        ${checkTrue "media-manager API ports are allowed on tailscale0 only" mediaManagementServicesReachableOverTailscale}
        ${checkTrue "media-manager API ports are not opened globally" mediaManagementServicesNotGlobal}
        ${checkTrue "media-manager API ports are not opened on other interfaces" mediaManagementServicesNotReachableOnOtherInterfaces}
        ${checkFalse "Radarr firewall opening is disabled globally" (drlight.services.radarr.openFirewall or false)}
        ${checkFalse "Sonarr firewall opening is disabled globally" (drlight.services.sonarr.openFirewall or false)}
        ${checkFalse "Lidarr firewall opening is disabled globally" (drlight.services.lidarr.openFirewall or false)}
        ${checkFalse "Bazarr firewall opening is disabled globally" (drlight.services.bazarr.openFirewall or false)}
        ${checkTrue "Bazarr starts after its Drlight-local Sonarr and Radarr services" (builtins.all (unit: builtins.elem unit ((mediaManagementService "bazarr").after or [])) ["sonarr.service" "radarr.service"])}
        ${checkTrue "Bazarr wants its Drlight-local Sonarr and Radarr services" (builtins.all (unit: builtins.elem unit ((mediaManagementService "bazarr").wants or [])) ["sonarr.service" "radarr.service"])}
        ${checkTrue "Mylar3 is an unprivileged system service" ((mediaManagementServiceConfig "mylar3").User or null == "mylar3" && (drlight.users.users.mylar3.isSystemUser or false))}
        ${checkEqual "Mylar3 uses isolated state directory" "mylar3" (mediaManagementServiceConfig "mylar3").StateDirectory or null}
        ${checkTrue "Mylar3 runs in the shared media group" ((mediaManagementServiceConfig "mylar3").Group or null == "users")}
        ${checkTrue "Mylar3 has a service health check" ((mediaManagementServiceConfig "mylar3").ExecStartPost or null != null)}
        ${checkTrue "Mylar3 service is enabled on Drlight" (drlight.services.mylar3.enable or false)}
        ${checkEqual "Mylar3 package uses its pinned version" "0.8.3" (mylar3Package.version or null)}
        ${checkTrue "Mylar3 package verifies runtime native image imports" (mylar3Package.doInstallCheck or false)}
        echo "  Mylar3 package runtime import check: ${mylar3Package}"
        ${checkTrue "media-management module is not selected by other machines" (lib.all (machine: !(hasModule "/modules/nixos/media-management.nix" machine)) (builtins.attrValues (builtins.removeAttrs catalog ["drlight"])))}
        ${checkTrue "no Arr, Mylar3, or Bazarr service is enabled on other machines" nonDrlightHasNoMediaManagers}
        ${checkFalse "media-manager apps are not exposed through Caddy" (lib.any (name: builtins.elem name caddyApps) ["radarr" "sonarr" "lidarr" "mylar3" "bazarr"])}
        ${lib.concatMapStringsSep "\n" (app: ''
          ${checkTrue "${app} has an API reconciliation unit" (builtins.hasAttr "${app}-media-config-sync" drlight.systemd.services)}
        '') ["radarr" "sonarr" "lidarr" "bazarr"]}
        ${checkTrue "Arr reconciliation imports its packaged shared Python helpers" (lib.hasInfix "media-app-reconciliation-scripts/servarr_reconcile.py" (drlight.systemd.services.radarr-media-config-sync.serviceConfig.ExecStart or ""))}
        ${checkTrue "Radarr admin auth reconciliation remains enabled without its Transmission client" (drlightWithRadarrAuthOnly.systemd.services ? radarr-media-config-sync)}
        ${checkTrue "auth-only Radarr reconciliation cannot read Transmission secrets" (builtins.elem "media-auth-radarr" (drlightWithRadarrAuthOnly.systemd.services.radarr-media-config-sync.serviceConfig.SupplementaryGroups or []) && !(builtins.elem "media-management-secrets" (drlightWithRadarrAuthOnly.systemd.services.radarr-media-config-sync.serviceConfig.SupplementaryGroups or [])))}
        ${checkTrue "Bazarr reconciliation imports its packaged shared Python helpers" (lib.hasInfix "media-app-reconciliation-scripts/bazarr_reconcile.py" (drlight.systemd.services.bazarr-media-config-sync.serviceConfig.ExecStart or ""))}
        ${checkTrue "Arr apps clear seedbox reverse-proxy URL bases for direct Tailscale access" (lib.all (app: (drlight.services.${app}.settings.server.urlbase or null) == "") ["radarr" "sonarr" "lidarr"])}
        ${checkEqual "Radarr's empty URL base is emitted to its migrated runtime config" "" (drlight.systemd.services.radarr.environment.RADARR__SERVER__URLBASE or null)}
        ${checkEqual "Sonarr's empty URL base is emitted to its migrated runtime config" "" (drlight.systemd.services.sonarr.environment.SONARR__SERVER__URLBASE or null)}
        ${checkTrue "Arr apps retain form authentication and Nix-managed external updates" (lib.all (app: (drlight.services.${app}.settings.auth.method or null) == "Forms" && (drlight.services.${app}.settings.auth.required or null) == "Enabled" && (drlight.services.${app}.settings.update.mechanism or null) == "external" && (drlight.services.${app}.settings.update.automatically or null) == false) ["radarr" "sonarr" "lidarr"])}
        ${checkTrue "Radarr reconciles its local library root" (builtins.elem "/srv/media/movies" (((drlight.myConfig.mediaManagement or {}).radarr or {}).rootFolders or []))}
        ${checkTrue "Sonarr reconciles its local library root" (builtins.elem "/srv/media/shows" (((drlight.myConfig.mediaManagement or {}).sonarr or {}).rootFolders or []))}
        ${checkTrue "Lidarr reconciles its local library root" (builtins.elem "/srv/media/music" (((drlight.myConfig.mediaManagement or {}).lidarr or {}).rootFolders or []))}
        ${checkTrue "Arr clients map seedbox downloads to local staging" (lib.all (app: (((((drlight.myConfig.mediaManagement or {}).${app} or {}).transmission or {}).localPath or null) == "/srv/media/.arr-staging")) ["radarr" "sonarr" "lidarr"])}
        ${checkFalse "Bazarr does not activate source-disabled Arr sync integrations by default" (drlight.myConfig.mediaManagement.bazarr.useSonarr || drlight.myConfig.mediaManagement.bazarr.useRadarr)}
        ${checkTrue "Mylar3's declarative settings use the local comic root" ((drlight.services.mylar3.settings.General.DESTINATION_DIR or null) == "/srv/media/comics")}
        ${checkTrue "Mylar3 keeps media organization behavior from the seedbox config" (drlight.services.mylar3.settings.General.CREATE_FOLDERS && !drlight.services.mylar3.settings.General.MOVE_FILES && !drlight.services.mylar3.settings.General.RENAME_FILES)}
        ${checkFalse "Mylar3 automatic updates stay under Nix package management" drlight.services.mylar3.settings.General.AUTO_UPDATE}
        ${checkTrue "Mylar3 retains its configured post-processing mode" drlight.services.mylar3.settings.PostProcess.POST_PROCESSING}
        ${checkEqual "Mylar3 uses a root URL base on Drlight's direct port" "/" (drlight.services.mylar3.settings.Interface.HTTP_ROOT or null)}
        ${checkEqual "Mylar3 preserves its Forms authentication mode" 2 (drlight.services.mylar3.settings.Interface.AUTHENTICATION or null)}
        ${checkEqual "Mylar3 admin username comes from its runtime Opnix file" "/run/secrets/mylar3-admin-username" (drlight.services.mylar3.settings.Interface.HTTP_USERNAME.secret or null)}
        ${checkEqual "Mylar3 admin password comes from its runtime Opnix file" "/run/secrets/mylar3-admin-password" (drlight.services.mylar3.settings.Interface.HTTP_PASSWORD.secret or null)}
        ${checkTrue "Mylar3 waits for Opnix secrets before rendering its protected config" (builtins.elem "opnix-secrets.service" ((mediaManagementService "mylar3").after or []) && builtins.elem "opnix-secrets.service" ((mediaManagementService "mylar3").requires or []))}
        ${checkEqual "Mylar3 retains its non-torrent downloader mode" 0 (drlight.services.mylar3.settings.Client.TORRENT_DOWNLOADER or null)}
        ${checkFalse "Mylar3 does not enable torrent downloads or search" (drlight.services.mylar3.settings.Torrents.ENABLE_TORRENTS or true || drlight.services.mylar3.settings.Torrents.ENABLE_TORRENT_SEARCH or true)}
        ${checkEqual "Mylar3 stores its INI beside its persistent database" "/var/lib/mylar3" drlight.services.mylar3.dataDir}
        ${checkTrue "Mylar3 overlays declared settings before startup" (lib.hasInfix "render-mylar3-config" (mediaManagementServiceConfig "mylar3").ExecStartPre)}
        ${checkFalse "Mylar3 can leave restored INI untouched during one-time root migration" (builtins.hasAttr "ExecStartPre" (drlightWithMylarSettingsManagementDisabled.systemd.services.mylar3.serviceConfig or {}))}
        ${checkEqual "media app login secrets use the expected Opnix fields" mediaAuthExpectedReferences (map (secret: secret.reference or null) mediaAuthSecrets)}
        ${checkEqual "media app login references resolve through the Opnix default vault" (map (reference: "op://Opnix/${reference}") mediaAuthExpectedReferences) (map (secret: secret.reference or null) opnixMediaAuthSecrets)}
        ${checkEqual "media app login secrets use restricted runtime paths" [
          "/run/secrets/radarr-admin-username"
          "/run/secrets/radarr-admin-password"
          "/run/secrets/sonarr-admin-username"
          "/run/secrets/sonarr-admin-password"
          "/run/secrets/lidarr-admin-username"
          "/run/secrets/lidarr-admin-password"
          "/run/secrets/bazarr-admin-username"
          "/run/secrets/bazarr-admin-password"
          "/run/secrets/mylar3-admin-username"
          "/run/secrets/mylar3-admin-password"
          "/run/secrets/jellyfin-admin-username"
          "/run/secrets/jellyfin-admin-password"
        ] (map (secret: secret.path or null) mediaAuthSecrets)}
        ${checkEqual "media app login secrets are root-owned and readable only by their app-specific groups" [
          "media-auth-radarr"
          "media-auth-radarr"
          "media-auth-sonarr"
          "media-auth-sonarr"
          "media-auth-lidarr"
          "media-auth-lidarr"
          "media-auth-bazarr"
          "media-auth-bazarr"
          "media-auth-mylar3"
          "media-auth-mylar3"
          "media-auth-jellyfin"
          "media-auth-jellyfin"
        ] (map (secret: secret.group or null) mediaAuthSecrets)}
        ${checkTrue "media app login secrets are owned by root with mode 0440" (builtins.all (secret: (secret.owner or null) == "root" && (secret.mode or null) == "0440") mediaAuthSecrets)}
        ${checkEqual "media app login secrets trigger only their owning app" (builtins.concatLists (map (app: [[app] [app]]) ["radarr" "sonarr" "lidarr" "bazarr" "mylar3" "jellyfin"])) (map (secret: secret.services or []) mediaAuthSecrets)}
        ${checkTrue "each media app account can read only its own login secret group" (builtins.all (app: builtins.elem "media-auth-${app.name}" (drlight.users.users.${app.name}.extraGroups or [])) mediaAuthApps)}
        ${checkTrue "media credential reconciliation waits for Opnix and its app" (builtins.all (app: let
          after = drlight.systemd.services.${app.sync}.after or [];
        in
          builtins.elem "opnix-secrets.service" after && (app.sync == app.name || builtins.elem "${app.name}.service" after))
        mediaAuthApps)}

        if [ "$failures" -ne 0 ]; then exit 1; fi
        echo "All Drlight media-management tests passed"
        touch $out
      '';

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
        ${checkTrue "Jellyfin streaming port is open" (builtins.elem 8096 drlight.networking.firewall.allowedTCPPorts)}
        ${checkFalse "Jellyfin HTTPS port is not opened" (builtins.elem 8920 drlight.networking.firewall.allowedTCPPorts)}
        ${checkTrue "Jellyfin discovery port is open" (builtins.elem 7359 drlight.networking.firewall.allowedUDPPorts)}
        ${checkFalse "DLNA discovery port is not opened" (builtins.elem 1900 drlight.networking.firewall.allowedUDPPorts)}
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
        ${checkTrue "Homepage includes every enabled Caddy app" (builtins.all (href: builtins.elem href sortedHomepageHrefs) expectedCaddyHomepageHrefs)}
        ${checkTrue "Homepage links all five Arr apps directly over Tailscale" (builtins.all (href: builtins.elem href sortedHomepageHrefs) expectedMediaManagerHomepageHrefs)}
        ${checkEqual "Homepage includes Caddy apps and direct Tailscale media links" expectedLocalHomepageHrefs sortedHomepageHrefs}
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
          ${checkTrue "scheduled upgrade guard checks systemd unit state" (lib.hasInfix "systemctl show --property=ActiveState --value \"$unit\"" (drlight.systemd.services.nixos-upgrade-scheduled.script or ""))}
          ${checkTrue "scheduled upgrade guard checks the upgrade and switch units" (lib.hasInfix "nixos-upgrade.service nixos-rebuild-switch-to-configuration.service" (drlight.systemd.services.nixos-upgrade-scheduled.script or ""))}
          ${checkTrue "scheduled upgrade guard skips an upgrade or switch already in progress" (lib.hasInfix "active|activating|deactivating|reloading" (drlight.systemd.services.nixos-upgrade-scheduled.script or ""))}
          ${checkTrue "scheduled upgrade guard waits for a newly started upgrade" (lib.hasInfix "systemctl start nixos-upgrade.service" (drlight.systemd.services.nixos-upgrade-scheduled.script or "") && !(lib.hasInfix "systemctl start --no-block nixos-upgrade.service" (drlight.systemd.services.nixos-upgrade-scheduled.script or "")))}
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
           ${checkTrue "Arr staging root is prepared on the media filesystem with group-write and setgid permissions" (lib.hasInfix "install -d -o root -g users -m 2775 /srv/media/.arr-staging" mediaManagementRootScript)}
           ${checkFalse "obsolete NVMe cache staging path is not prepared" (lib.any (rule: lib.hasInfix "/srv/local/cache/ultra" rule) localStorageTmpfiles || lib.hasInfix "/srv/local/cache/ultra" mediaManagementRootScript)}
           ${checkEqual "NVMe machine-specific state directory is prepared" "d /srv/local/state 0750 root root - -" (lib.findFirst (rule: lib.hasInfix "/srv/local/state" rule) null localStorageTmpfiles)}
           ${checkEqual "NVMe cache mount is ext4" "ext4" (localStorageFilesystem.fsType or null)}
           ${checkTrue "Jellyfin declares its media mount requirement in the unit section" (builtins.elem "/srv/media" jellyfinMountRequirements)}
           ${checkFalse "Jellyfin does not emit RequiresMountsFor in the service section" (jellyfinService.serviceConfig ? RequiresMountsFor)}
           ${checkTrue "Jellyfin starts after ZFS automatic mounts complete" (builtins.elem "zfs-mount.service" (drlight.systemd.services.jellyfin.after or []))}
           ${checkEqual "Jellyfin will not start with the underlying empty directory" "/srv/media" (jellyfinUnitConfig.ConditionPathIsMountPoint or null)}
           ${checkTrue "Drlight selects the torrent download-staging module" (hasModule "/modules/nixos/ultra-media-download-stage.nix" drlightMachine)}
           ${checkFalse "legacy organized-library sync service is removed" (drlight.systemd.services ? ultra-media-sync)}
           ${checkFalse "legacy organized-library sync timer is removed" (drlight.systemd.timers ? ultra-media-sync)}
           ${checkFalse "legacy media-root Opnix reference is removed" (onePasswordSecrets ? ultraMediaStageMediaRoot)}
           ${checkFalse "legacy library source Opnix references are removed" (onePasswordSecrets ? ultraMediaStageMoviesSource || onePasswordSecrets ? ultraMediaStageShowsSource || onePasswordSecrets ? ultraMediaStageMusicSource || onePasswordSecrets ? ultraMediaStageComicsSource)}
           ${checkFalse "SSH port is no longer an Opnix secret" (onePasswordSecrets ? ultraMediaStagePort)}
           ${checkTrue "staging uses the default SSH port 22" (lib.hasInfix "--ssh-port 22" ultraDownloadStageCommand)}
           ${checkFalse "completed-download staging option defaults to false" (drlight.myConfig.ultraMediaDownloadStage.enable or false)}
           ${checkFalse "completed-download staging is disabled by default" ultraDownloadStageEnabled}
           ${checkFalse "completed-download staging timer is not enabled by default" (builtins.elem "timers.target" (ultraDownloadStageTimer.wantedBy or []))}
           ${checkTrue "explicitly enabling completed-download staging enables its timer" (builtins.elem "timers.target" (ultraDownloadStageEnabledTimer.wantedBy or []))}
           ${checkEqual "completed-download staging timer activates its separate service" "ultra-media-download-stage.service" (ultraDownloadStageTimerConfig.Unit or null)}
           ${checkEqual "completed-download staging timer uses an hourly schedule" "hourly" (ultraDownloadStageTimerConfig.OnCalendar or null)}
           ${checkEqual "completed-download staging is a oneshot service" "oneshot" (ultraDownloadStageServiceConfig.Type or null)}
           ${checkEqual "completed-download staging runs as the existing Ultra sync user" "ultra-sync" (ultraDownloadStageServiceConfig.User or null)}
           ${checkEqual "completed-download staging runs in the shared media group" "users" (ultraDownloadStageServiceConfig.Group or null)}
           ${checkEqual "completed-download staging requires the mounted media filesystem" "/srv/media" (ultraDownloadStageService.unitConfig.ConditionPathIsMountPoint or null)}
           ${checkEqual "report-only cleanup is triggered only after successful staging" "ultra-media-cleanup.service" (ultraDownloadStageService.unitConfig.OnSuccess or null)}
           ${checkEqual "cleanup is a report-only oneshot under the Ultra sync account" ["oneshot" "ultra-sync" "users"] [(ultraCleanupServiceConfig.Type or null) (ultraCleanupServiceConfig.User or null) (ultraCleanupServiceConfig.Group or null)]}
           ${checkTrue "cleanup command explicitly selects report-only mode" (lib.hasInfix "ultra-media-cleanup.py" ultraCleanupCommand && lib.hasInfix "--report-only" ultraCleanupCommand)}
           ${checkTrue "cleanup service has no timer or activation target" (!(builtins.elem "timers.target" (ultraCleanupTimer.wantedBy or [])) && !(builtins.elem "multi-user.target" (ultraCleanupService.wantedBy or [])))}
           ${checkTrue "cleanup cannot access the network or credentials" ((ultraCleanupServiceConfig.PrivateNetwork or false) && (ultraCleanupServiceConfig.NoNewPrivileges or false) && !(lib.hasInfix "opnix-secrets" ultraSyncCleanupModuleSource) && !(lib.hasInfix "/run/secrets" ultraSyncCleanupModuleSource))}
           ${checkTrue "cleanup and staging serialize on the same operation lock" (lib.hasInfix ".operation.lock" ultraSyncStagingSource && lib.hasInfix ".operation.lock" ultraSyncPolicySource)}
           ${checkFalse "cleanup has no data deletion operation or destructive service mode" (lib.hasInfix "torrent-remove" ultraSyncPolicySource || lib.hasInfix "torrent-remove" ultraSyncCleanupModuleSource || lib.hasInfix "--delete" ultraSyncCleanupModuleSource)}
           ${checkTrue "completed-download staging writes only to the hidden stage root" (builtins.elem "/srv/media/.arr-staging" (ultraDownloadStageServiceConfig.ReadWritePaths or []))}
           ${checkTrue "completed-download staging waits for ZFS, media roots, and OpNix secrets" (builtins.all (unit: builtins.elem unit (ultraDownloadStageService.after or [])) ["zfs-mount.service" "media-management-roots.service" "opnix-secrets.service"] && builtins.all (unit: builtins.elem unit (ultraDownloadStageService.requires or [])) ["zfs-mount.service" "media-management-roots.service" "opnix-secrets.service"])}
           ${checkTrue "completed-download staging service runs the dedicated Python adapter" (lib.hasInfix "ultra-media-download-stage.py" ultraDownloadStageCommand && lib.hasInfix "--stage-downloads" ultraDownloadStageCommand)}
           ${checkTrue "stage runtime validates individually supplied RPC URL and completed-download root fields" (lib.hasInfix "rpc_url" ultraSyncStagingSource && lib.hasInfix "download_root" ultraSyncStagingSource && lib.hasInfix "normalize_download_root" ultraSyncStagingSource)}
           ${checkTrue "the retention policy evaluator remains available separately from staging" (lib.hasInfix "evaluate_retention" ultraSyncPolicySource)}
           ${checkTrue "stage runtime reports aggregate counters only" (lib.hasInfix "staging " ultraSyncStagingSource && lib.hasInfix "reason=" ultraSyncStagingSource)}
           ${checkFalse "stage rsync never deletes seedbox or local files" (lib.hasInfix "--delete" ultraSyncStagingSource || lib.hasInfix "--remove-source-files" ultraSyncStagingSource)}
           ${checkEqual "Transmission RPC username uses the unqualified OpNix field" "Ultra - Transmission/username" (ultraStageRpcUsernameSecret.reference or null)}
           ${checkEqual "Transmission RPC password uses the unqualified OpNix field" "Ultra - Transmission/password" (ultraStageRpcPasswordSecret.reference or null)}
           ${checkTrue "Transmission RPC credentials are scoped to staging and local Arr reconciliation" ((ultraStageRpcUsernameSecret.services or []) == (["ultra-media-download-stage"] ++ ["radarr-media-config-sync" "sonarr-media-config-sync" "lidarr-media-config-sync"]) && (ultraStageRpcPasswordSecret.services or []) == (["ultra-media-download-stage"] ++ ["radarr-media-config-sync" "sonarr-media-config-sync" "lidarr-media-config-sync"]))}
           ${checkEqual "Transmission RPC username resolves through the Opnix default vault" "op://Opnix/Ultra - Transmission/username" (opnixUltraStageRpcUsernameSecret.reference or null)}
           ${checkEqual "Transmission RPC password resolves through the Opnix default vault" "op://Opnix/Ultra - Transmission/password" (opnixUltraStageRpcPasswordSecret.reference or null)}
           ${checkTrue "the SSH key is scoped only to staging" ((ultraStageKeySecret.services or []) == ["ultra-media-download-stage"])}
           ${checkEqual "Drlight uses Opnix as its default vault" "Opnix" (drlight.myConfig.onepassword.defaultVault or null)}
           ${checkEqual "Drlight Cloudflare secret uses the Opnix item and field" "Cloudflare DNS API Token/credential" (onePasswordSecrets.cloudflareApiToken.reference or null)}
           ${checkEqual "Drlight Cloudflare secret resolves to the Opnix vault" "op://Opnix/Cloudflare DNS API Token/credential" (opnixSecrets.cloudflareApiToken.reference or null)}
           ${checkEqual "stage SSH private key uses its runtime path" "/run/secrets/ultra-media-stage-key" (ultraStageKeySecret.path or null)}
           ${checkEqual "stage uses the minimal Opnix field contract" ultraStageExpectedReferences (map (secret: secret.reference or null) ultraStageSecrets)}
           ${checkTrue "SSH staging secrets remain private to the stage account" (builtins.all (secret: (secret.owner or null) == "ultra-sync" && (secret.group or null) == "users" && (secret.mode or null) == "0400") ultraStagePrivateSecrets)}
           ${checkTrue "Opnix keeps SSH staging secrets private to the stage account" (builtins.all (secret: (secret.owner or null) == "ultra-sync" && (secret.group or null) == "users" && (secret.mode or null) == "0400") opnixUltraStagePrivateSecrets)}
           ${checkTrue "Transmission and completed-path secrets are readable only by the media secrets group" (builtins.all (secret: (secret.owner or null) == "root" && (secret.group or null) == "media-management-secrets" && (secret.mode or null) == "0440") ultraStageSharedSecrets)}
           ${checkTrue "Opnix materializes shared RPC values with restricted media-group permissions" (builtins.all (secret: (secret.owner or null) == "root" && (secret.group or null) == "media-management-secrets" && (secret.mode or null) == "0440") opnixUltraStageSharedSecrets)}
           ${checkTrue "stage and Arr reconcilers receive the dedicated media secrets group" (builtins.elem "media-management-secrets" (ultraDownloadStageServiceConfig.SupplementaryGroups or []) && builtins.all (app: builtins.elem "media-management-secrets" ((builtins.getAttr "${app}-media-config-sync" drlight.systemd.services).serviceConfig.SupplementaryGroups or [])) ["radarr" "sonarr" "lidarr"] && builtins.hasAttr "media-management-secrets" drlight.users.groups)}
           ${checkTrue "staging fields use unqualified references resolved by Opnix" (builtins.all (name: let
            secret = onePasswordSecrets.${name} or {};
            resolved = opnixSecrets.${name} or {};
          in
            (secret.reference or "") != "" && !(lib.hasPrefix "op://" (secret.reference or "")) && !(lib.hasPrefix "Opnix/" (secret.reference or "")) && (resolved.reference or null) == "op://Opnix/${secret.reference or ""}")
          ultraStageSecretNames)}
           ${checkTrue "the SSH key reference is unqualified and resolved through Opnix" ((ultraStageKeySecret.reference or "") == "Ultra Media Sync Key/private key" && (opnixUltraStageKeySecret.reference or null) == "op://Opnix/Ultra Media Sync Key/private key")}
           ${checkEqual "Drlight uses Opnix as its default vault" "Opnix" (drlight.myConfig.onepassword.defaultVault or null)}
           ${checkTrue "Nix prepares the six media folders including comics" (builtins.all (path: lib.hasInfix path mediaLibraryFoldersScript) ["/srv/media/audiobooks" "/srv/media/books" "/srv/media/comics" "/srv/media/movies" "/srv/media/music" "/srv/media/shows"])}
           ${checkFalse "Nix does not create a Podcasts folder" (lib.hasInfix "/srv/media/podcasts" mediaLibraryFoldersScript)}
           ${checkTrue "Nix prepares media folders after ZFS mount and before Jellyfin" (builtins.elem "zfs-mount.service" (mediaLibraryFoldersService.after or []) && builtins.elem "jellyfin.service" (mediaLibraryFoldersService.before or []) && builtins.elem "media-library-folders.service" (jellyfinService.after or []))}
           ${checkFalse "Jellyfin libraries remain configured through the UI, not an API sync service" (drlight.systemd.services ? jellyfin-declarative-config)}
           ${checkEqual "Jellyfin admin username uses the Opnix item field" "Jellyfin/username" (onePasswordSecrets.jellyfinAdminUsername.reference or null)}
           ${checkEqual "Jellyfin admin password uses the Opnix item field" "Jellyfin/password" (onePasswordSecrets.jellyfinAdminPassword.reference or null)}
           ${checkEqual "Jellyfin admin password resolves through Opnix" "op://Opnix/Jellyfin/password" (opnixSecrets.jellyfinAdminPassword.reference or null)}
           ${checkTrue "Jellyfin admin auth verifier runs after Jellyfin and Opnix" (builtins.all (unit: builtins.elem unit (drlight.systemd.services.jellyfin-admin-auth.after or [])) ["jellyfin.service" "opnix-secrets.service"] && builtins.elem "jellyfin.service" (drlight.systemd.services.jellyfin-admin-auth.wantedBy or []))}
           ${checkTrue "Jellyfin admin verifier uses the dedicated runtime authentication script" (lib.hasInfix "jellyfin_admin_auth.py" (drlight.systemd.services.jellyfin-admin-auth.serviceConfig.ExecStart or ""))}

           if ${pkgs.fakeroot}/bin/fakeroot ${pkgs.bash}/bin/bash <<'EOF'
          set -e
          umask 0002
          mkdir -p "$TMPDIR/restrictive-source/library" "$TMPDIR/normalized-destination"
          printf 'fixture media bytes\n' > "$TMPDIR/restrictive-source/library/movie.mkv"
          chmod 0700 "$TMPDIR/restrictive-source"
          chmod 2700 "$TMPDIR/restrictive-source/library"
          chmod 4700 "$TMPDIR/restrictive-source/library/movie.mkv"
          chmod 2775 "$TMPDIR/normalized-destination"
          touch -d @1000000000 "$TMPDIR/restrictive-source/library/movie.mkv"
          touch -d @1000000000 "$TMPDIR/restrictive-source/library"
          ${pkgs.rsync}/bin/rsync --recursive --times --omit-dir-times --no-perms --chmod=Du=rwx,Dg=rwx,Do=rx,Fu=rw,Fg=rw,Fo=r,ugo-s,o-t "$TMPDIR/restrictive-source/" "$TMPDIR/normalized-destination/"
          copied_root_mode=$(stat -c '%a' "$TMPDIR/normalized-destination")
          copied_dir_mode=$(stat -c '%a' "$TMPDIR/normalized-destination/library")
          copied_file_mode=$(stat -c '%a' "$TMPDIR/normalized-destination/library/movie.mkv")
          source_dir_mtime=$(stat -c '%Y' "$TMPDIR/restrictive-source/library")
          copied_dir_mtime=$(stat -c '%Y' "$TMPDIR/normalized-destination/library")
          source_file_mtime=$(stat -c '%Y' "$TMPDIR/restrictive-source/library/movie.mkv")
          copied_file_mtime=$(stat -c '%Y' "$TMPDIR/normalized-destination/library/movie.mkv")
          if [ "$copied_root_mode" = 2775 ]; then
            echo "  Real rsync leaves the shared destination root permissions unchanged: OK"
          else
            echo "FAIL: Real rsync changed the shared destination root mode to $copied_root_mode instead of 2775"
            exit 1
          fi
          if [ "$copied_dir_mode" = 775 ] && [ "$copied_file_mode" = 664 ]; then
            echo "  Real rsync normalizes new restrictive/set-ID source modes to 775/664: OK"
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
  drlightMediaManagementTest =
    if checks == null
    then skipped "drlight-media-management"
    else checks.drlightMediaManagementTest;
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
