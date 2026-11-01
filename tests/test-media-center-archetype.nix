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
  drlightMachine = catalog.drlight;

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
            [(observabilityInventory.machineModule drlightMachine)]
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
      caddyApps = builtins.attrNames (drlight.myConfig.caddy.apps or {});
      resticJobs = drlight.services.restic.backups or {};
      backupPaths = drlight.myConfig.backup.paths or [];
      onePasswordSecrets = drlight.myConfig.onepassword.secrets or {};
      secretValues = builtins.attrValues onePasswordSecrets;
      mediaMount = drlight.fileSystems."/srv/media" or {};
      compatibilityMediaMount = drlight.fileSystems."/media" or {};
      jellyfinMountRequirements = drlight.systemd.services.jellyfin.serviceConfig.RequiresMountsFor or [];
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

        ${checkEqual "Homepage exposes only local Jellyfin and Grafana" expectedLocalHomepageHrefs sortedHomepageHrefs}
        ${checkEqual "Caddy routes only dashboard and local Jellyfin/Grafana" expectedLocalCaddyRoutes (builtins.sort builtins.lessThan caddyRoutes)}
        ${checkEqual "Caddy app configuration only includes dashboard and local Jellyfin/Grafana" expectedLocalCaddyApps (builtins.sort builtins.lessThan caddyApps)}
        ${checkEqual "Caddy proxies only to local Homepage, Grafana, and Jellyfin" expectedLocalCaddyUpstreams actualLocalCaddyUpstreams}

        if [ "$failures" -ne 0 ]; then exit 1; fi
        echo "All drlight media presentation tests passed"
        touch $out
      '';

      drlightMediaStorageTest = pkgs.runCommand "test-drlight-media-storage" {} ''
        failures=0
        echo "=== Evaluating drlight ZFS media storage and Jellyfin mount dependency ==="

        ${checkTrue "existing media pool is imported" (builtins.elem "media" (drlight.boot.zfs.extraPools or []))}
        ${checkEqual "primary media mount device" "media/library" (mediaMount.device or null)}
        ${checkEqual "primary media mount filesystem" "zfs" (mediaMount.fsType or null)}
        ${checkEqual "compatibility media mount device" "media/library" (compatibilityMediaMount.device or null)}
        ${checkEqual "compatibility media mount filesystem" "zfs" (compatibilityMediaMount.fsType or null)}
        ${checkTrue "Jellyfin waits for the media mount" (builtins.elem "/srv/media" jellyfinMountRequirements)}

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
  drlightNoNixarrBackupTest =
    if checks == null
    then skipped "drlight-no-nixarr-backup"
    else checks.drlightNoNixarrBackupTest;
}
