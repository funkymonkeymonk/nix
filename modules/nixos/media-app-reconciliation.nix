{
  config,
  lib,
  pkgs,
  utils,
  ...
}: let
  inherit (lib) mkEnableOption mkOption types;

  mediaCfg = config.myConfig.mediaManagement;
  mediaSecretsGroup = "media-management-secrets";
  apiKeyDirectory = "/run/media-app-api-keys";
  stageRoot = "/srv/media/.arr-staging";

  secretFileOption = default:
    mkOption {
      type = types.str;
      inherit default;
      description = "Runtime file containing a secret or remote path; its contents are never evaluated by Nix.";
    };

  transmissionOptions = app: {
    enable = mkEnableOption "managed remote Transmission client for ${app}";
    category = mkOption {
      type = types.str;
      default = app;
      description = "Transmission category assigned by ${app}.";
    };
    localPath = mkOption {
      type = types.str;
      default = stageRoot;
      description = "Local path where the download staging job materializes completed data.";
    };
    rpcUrlFile = secretFileOption "/run/secrets/ultra-media-stage-rpc-url";
    rpcUsernameFile = secretFileOption "/run/secrets/ultra-media-stage-rpc-username";
    rpcPasswordFile = secretFileOption "/run/secrets/ultra-media-stage-rpc-password";
    remotePathFile = secretFileOption "/run/secrets/ultra-media-stage-download-root";
  };

  arrOptions = app: root: {
    rootFolders = mkOption {
      type = types.listOf types.str;
      default = [root];
      description = "Local application library roots managed through the app API.";
    };
    transmission = mkOption {
      type = types.submodule {options = transmissionOptions app;};
      default = {};
    };
  };

  arrServices = {
    radarr = {
      apiVersion = 3;
      port = config.services.radarr.settings.server.port;
      configFile = "${config.services.radarr.dataDir}/config.xml";
    };
    sonarr = {
      apiVersion = 3;
      port = config.services.sonarr.settings.server.port;
      configFile = "${config.services.sonarr.dataDir}/config.xml";
    };
    lidarr = {
      apiVersion = 1;
      port = config.services.lidarr.settings.server.port;
      configFile = "${config.services.lidarr.dataDir}/config.xml";
    };
  };

  python = pkgs.python3.withPackages (pythonPackages: [pythonPackages.pyyaml]);
  scriptsDir = builtins.path {
    path = ./scripts;
    name = "media-app-reconciliation-scripts";
  };

  apiKeyFile = name: "${apiKeyDirectory}/${name}";

  apiKeyExtractor = {
    description,
    service,
    source,
    format,
  }: {
    inherit description;
    after = ["${service}.service"];
    wantedBy = ["${service}.service"];
    serviceConfig = {
      Type = "oneshot";
      User = "root";
      Group = "${service}-api";
      UMask = "0027";
      ExecStart = utils.escapeSystemdExecArgs [
        "${python}/bin/python"
        "${scriptsDir}/extract_media_api_key.py"
        "--format"
        format
        "--source"
        source
        "--output"
        (apiKeyFile service)
      ];
    };
  };

  arrServiceConfig = app: service: let
    appCfg = mediaCfg.${app};
    transmission = appCfg.transmission;
    configFile = pkgs.writeText "${app}-media-reconcile.json" (builtins.toJSON {
      baseUrl = "http://127.0.0.1:${toString service.port}/api/v${toString service.apiVersion}";
      configXml = service.configFile;
      rootFolders = appCfg.rootFolders;
      transmission = {
        name = "Transmission";
        category = transmission.category;
        localPath = transmission.localPath;
        rpcUrl.secret = transmission.rpcUrlFile;
        username.secret = transmission.rpcUsernameFile;
        password.secret = transmission.rpcPasswordFile;
        remotePath.secret = transmission.remotePathFile;
      };
    });
  in {
    description = "Reconcile declarative media settings for ${app}";
    after = ["${app}.service" "${app}-media-api-key.service" "opnix-secrets.service"];
    wants = ["${app}-media-api-key.service" "opnix-secrets.service"];
    requires = ["${app}-media-api-key.service" "opnix-secrets.service"];
    wantedBy = ["${app}.service"];
    serviceConfig = {
      Type = "oneshot";
      User = app;
      Group = "${app}-api";
      SupplementaryGroups = [mediaSecretsGroup];
      UMask = "0077";
      ProtectSystem = "strict";
      ProtectHome = true;
      NoNewPrivileges = true;
      RestrictAddressFamilies = ["AF_INET" "AF_INET6" "AF_UNIX"];
      ExecStart = "${python}/bin/python ${scriptsDir}/servarr_reconcile.py --config ${configFile}";
    };
  };

  bazarrConfig = pkgs.writeText "bazarr-media-reconcile.json" (builtins.toJSON {
    bazarrBaseUrl = "http://127.0.0.1:${toString config.services.bazarr.settings.general.port}";
    bazarrApiKeyFile = apiKeyFile "bazarr";
    sonarr = {
      baseUrl = "http://127.0.0.1:${toString config.services.sonarr.settings.server.port}";
      apiKeyFile = apiKeyFile "sonarr";
    };
    radarr = {
      baseUrl = "http://127.0.0.1:${toString config.services.radarr.settings.server.port}";
      apiKeyFile = apiKeyFile "radarr";
    };
  });

  arrKeyServices = lib.mapAttrs' (name: service:
    lib.nameValuePair "${name}-media-api-key" (apiKeyExtractor {
      description = "Extract the ${name} API key for local integrations";
      service = name;
      source = service.configFile;
      format = "xml";
    }))
  arrServices;

  arrSyncServices = lib.mapAttrs' (name: service:
    lib.nameValuePair "${name}-media-config-sync" (arrServiceConfig name service))
  arrServices;

  groups = lib.genAttrs (map (name: "${name}-api") (builtins.attrNames arrServices) ++ ["bazarr-api" mediaSecretsGroup]) (_: {});

  hasArrSync = app: config.services.${app}.enable && mediaCfg.${app}.transmission.enable;
  enabledArrApps = builtins.filter hasArrSync (builtins.attrNames arrServices);

  bazarrEnabled = config.services.bazarr.enable;
  bazarrKeyService = apiKeyExtractor {
    description = "Extract the Bazarr API key for local integrations";
    service = "bazarr";
    source = "${config.services.bazarr.dataDir}/config/config.yaml";
    format = "yaml";
  };

  bazarrSyncService = {
    description = "Reconcile Bazarr's Drlight-local Arr connections";
    after = ["bazarr.service" "bazarr-media-api-key.service" "radarr-media-api-key.service" "sonarr-media-api-key.service" "opnix-secrets.service"];
    wants = ["bazarr-media-api-key.service" "radarr-media-api-key.service" "sonarr-media-api-key.service" "opnix-secrets.service"];
    requires = ["bazarr-media-api-key.service" "radarr-media-api-key.service" "sonarr-media-api-key.service" "opnix-secrets.service"];
    wantedBy = ["bazarr.service"];
    serviceConfig = {
      Type = "oneshot";
      User = "bazarr";
      Group = "bazarr-api";
      SupplementaryGroups = ["radarr-api" "sonarr-api"];
      UMask = "0077";
      ProtectSystem = "strict";
      ProtectHome = true;
      NoNewPrivileges = true;
      RestrictAddressFamilies = ["AF_INET" "AF_INET6" "AF_UNIX"];
      ExecStart = "${python}/bin/python ${scriptsDir}/bazarr_reconcile.py --config ${bazarrConfig}";
    };
  };

  mylarSettingsJson = pkgs.writeText "mylar3-declarative-settings.json" (builtins.toJSON config.services.mylar3.settings);
  mylarConfigRenderer = pkgs.writeShellScript "render-mylar3-config" ''
    exec ${python}/bin/python ${scriptsDir}/mylar3_config.py \
      --settings ${mylarSettingsJson} \
      --config ${lib.escapeShellArg "${config.services.mylar3.dataDir}/config.ini"}
  '';
in {
  options.myConfig.mediaManagement = {
    radarr = mkOption {
      type = types.submodule {options = arrOptions "radarr" "/srv/media/movies";};
      default = {};
    };
    sonarr = mkOption {
      type = types.submodule {options = arrOptions "sonarr" "/srv/media/shows";};
      default = {};
    };
    lidarr = mkOption {
      type = types.submodule {options = arrOptions "lidarr" "/srv/media/music";};
      default = {};
    };
  };

  config = {
    users.groups = groups;
    systemd.tmpfiles.rules = ["d ${apiKeyDirectory} 0755 root root - -"];

    systemd.services = lib.mkMerge [
      arrKeyServices
      (lib.genAttrs (map (name: "${name}-media-config-sync") enabledArrApps)
        (serviceName: arrSyncServices.${serviceName} or {}))
      (lib.mkIf bazarrEnabled {
        bazarr-media-api-key = bazarrKeyService;
        bazarr-media-config-sync = bazarrSyncService;
      })
      {
        mylar3.serviceConfig.ExecStartPre = lib.mkIf config.services.mylar3.enable mylarConfigRenderer;
      }
    ];

    users.users.bazarr.extraGroups = lib.mkIf bazarrEnabled ["bazarr-api" "radarr-api" "sonarr-api"];
  };
}
