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
  mediaAuthApps = [
    {
      name = "radarr";
      item = "Radarr";
      passwordField = "password";
    }
    {
      name = "sonarr";
      item = "Sonarr";
      passwordField = "password";
    }
    {
      name = "lidarr";
      item = "Lidarr";
      passwordField = "password";
    }
    {
      name = "bazarr";
      item = "Bazaar";
      passwordField = "password";
    }
    {
      name = "mylar3";
      item = "Mylar3";
      passwordField = "password";
    }
    {
      name = "jellyfin";
      item = "Jellyfin";
      passwordField = "password";
    }
  ];
  mediaAuthSecretPath = app: field: "/run/secrets/${app}-admin-${field}";
  mkMediaAuthSecret = app: field: referenceField: {
    reference = "${app.item}/${referenceField}";
    path = mediaAuthSecretPath app.name field;
    owner = "root";
    group = "media-auth-${app.name}";
    mode = "0440";
    services = [app.name];
  };
  mediaAuthSecrets = lib.listToAttrs (lib.concatMap (app: [
      (lib.nameValuePair "${app.name}AdminUsername" (mkMediaAuthSecret app "username" "username"))
      (lib.nameValuePair "${app.name}AdminPassword" (mkMediaAuthSecret app "password" app.passwordField))
    ])
    mediaAuthApps);
  jellyfinAuthConfig = pkgs.writeText "jellyfin-admin-auth.json" (builtins.toJSON {
    baseUrl = "http://127.0.0.1:8096";
    usernameFile = mediaAuthSecretPath "jellyfin" "username";
    passwordFile = mediaAuthSecretPath "jellyfin" "password";
  });
  jellyfinAuthService = {
    description = "Verify the declared Jellyfin administrator credentials";
    after = ["jellyfin.service" "opnix-secrets.service"];
    wants = ["jellyfin.service" "opnix-secrets.service"];
    requires = ["jellyfin.service" "opnix-secrets.service"];
    wantedBy = ["jellyfin.service"];
    serviceConfig = {
      Type = "oneshot";
      User = "jellyfin";
      Group = "jellyfin";
      SupplementaryGroups = ["media-auth-jellyfin"];
      UMask = "0077";
      ProtectSystem = "strict";
      ProtectHome = true;
      NoNewPrivileges = true;
      RestrictAddressFamilies = ["AF_INET" "AF_INET6" "AF_UNIX"];
      ExecStart = "${pkgs.python3}/bin/python ${scriptsDir}/jellyfin_admin_auth.py --config ${jellyfinAuthConfig}";
    };
  };

  secretFileOption = default:
    mkOption {
      type = types.str;
      inherit default;
      description = "Runtime file containing a secret or remote path; its contents are never evaluated by Nix.";
    };

  transmissionOptions = app: {
    enable = mkEnableOption "managed remote Transmission client for ${app}";
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
    adminAuth = mkOption {
      type = types.submodule {
        options = {
          enable = lib.mkEnableOption "declarative ${app} Forms-auth credentials";
          usernameFile = secretFileOption (mediaAuthSecretPath app "username");
          passwordFile = secretFileOption (mediaAuthSecretPath app "password");
        };
      };
      default = {};
      description = "Runtime-only administrator credentials reconciled through the local Arr API.";
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
      application = app;
      baseUrl = "http://127.0.0.1:${toString service.port}/api/v${toString service.apiVersion}";
      configXml = service.configFile;
      rootFolders = appCfg.rootFolders;
      auth = lib.optionalAttrs appCfg.adminAuth.enable {
        username.secret = appCfg.adminAuth.usernameFile;
        password.secret = appCfg.adminAuth.passwordFile;
      };
      transmission = lib.optionalAttrs transmission.enable {
        name = "Transmission";
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
      SupplementaryGroups = ["media-auth-${app}"] ++ lib.optionals transmission.enable [mediaSecretsGroup];
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
    useSonarr = mediaCfg.bazarr.useSonarr;
    useRadarr = mediaCfg.bazarr.useRadarr;
    sonarr = {
      baseUrl = "http://127.0.0.1:${toString config.services.sonarr.settings.server.port}";
      apiKeyFile = apiKeyFile "sonarr";
    };
    auth = {
      usernameFile = mediaAuthSecretPath "bazarr" "username";
      passwordFile = mediaAuthSecretPath "bazarr" "password";
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

  groups = lib.genAttrs (
    map (name: "${name}-api") (builtins.attrNames arrServices)
    ++ ["bazarr-api" mediaSecretsGroup]
    ++ map (app: "media-auth-${app.name}") mediaAuthApps
  ) (_: {});

  hasArrSync = app: config.services.${app}.enable && (mediaCfg.${app}.transmission.enable || mediaCfg.${app}.adminAuth.enable);
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
      SupplementaryGroups = ["radarr-api" "sonarr-api" "media-auth-bazarr"];
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
    bazarr = mkOption {
      type = types.submodule {
        options = {
          useSonarr = mkOption {
            type = types.bool;
            default = false;
            description = "Enable Bazarr's Sonarr synchronization after migration.";
          };
          useRadarr = mkOption {
            type = types.bool;
            default = false;
            description = "Enable Bazarr's Radarr synchronization after migration.";
          };
        };
      };
      default = {};
    };
  };

  config = {
    myConfig.onepassword.secrets = mediaAuthSecrets;
    services.onepassword-secrets.enable = true;

    users.groups = groups;
    users.users = lib.genAttrs (map (app: app.name) mediaAuthApps) (app: {
      extraGroups = ["media-auth-${app}"] ++ lib.optionals (app == "bazarr" && bazarrEnabled) ["bazarr-api" "radarr-api" "sonarr-api"];
    });
    systemd.tmpfiles.rules = ["d ${apiKeyDirectory} 0755 root root - -"];

    systemd.services = lib.mkMerge [
      arrKeyServices
      (lib.genAttrs (map (name: "${name}-media-config-sync") enabledArrApps)
        (serviceName: arrSyncServices.${serviceName} or {}))
      (lib.mkIf bazarrEnabled {
        bazarr-media-api-key = bazarrKeyService;
        bazarr-media-config-sync = bazarrSyncService;
      })
      (lib.mkIf config.services.mylar3.enable {
        mylar3 = {
          after = ["opnix-secrets.service"];
          wants = ["opnix-secrets.service"];
          requires = ["opnix-secrets.service"];
          serviceConfig = {
            SupplementaryGroups = ["media-auth-mylar3"];
            ExecStartPre = lib.mkIf config.services.mylar3.manageSettingsFile mylarConfigRenderer;
          };
        };
      })
      (lib.mkIf config.services.jellyfin.enable {
        jellyfin-admin-auth = jellyfinAuthService;
      })
    ];
  };
}
