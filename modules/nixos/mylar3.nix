{
  config,
  lib,
  pkgs,
  utils,
  ...
}: let
  pythonPackages = pkgs.python312Packages;
  cfscrape = pythonPackages.cfscrape.overridePythonAttrs (oldAttrs: {
    postPatch =
      (oldAttrs.postPatch or "")
      + ''
        substituteInPlace cfscrape/__init__.py --replace-fail 'from urllib3.util.ssl_ import create_urllib3_context, DEFAULT_CIPHERS' 'from urllib3.util.ssl_ import create_urllib3_context; DEFAULT_CIPHERS = "DEFAULT:!ECDHE+SHA:!AES128-SHA:!AESCCM:!DHE:!ARIA"'
      '';
  });
  pystun = pythonPackages.buildPythonPackage {
    pname = "pystun";
    version = "0.1.0";
    src = pkgs.fetchPypi {
      pname = "pystun";
      version = "0.1.0";
      hash = "sha256-eHotHBMororDEVKg1tlrLwKrhnf+vcJeRjwsj+40Z58=";
    };
    pyproject = true;
    build-system = [pythonPackages.setuptools];
    doCheck = false;
    pythonImportsCheck = ["stun"];
  };
  mylarPython = pkgs.python312.withPackages (pythonPackages: [
    pythonPackages.apscheduler
    pythonPackages.beautifulsoup4
    cfscrape
    pythonPackages.cheroot
    pythonPackages.cherrypy
    pythonPackages.configparser
    pythonPackages.feedparser
    pythonPackages.mako
    pythonPackages.natsort
    pythonPackages.packaging
    pythonPackages.pillow
    pythonPackages.portend
    pythonPackages.pycryptodome
    pystun
    pythonPackages.pytz
    pythonPackages.rarfile
    pythonPackages.requests
    pythonPackages.pysocks
    pythonPackages.simplejson
    pythonPackages.six
    pythonPackages.tenacity
    pythonPackages.tzlocal
    pythonPackages.urllib3
  ]);
  mylar3Package = pkgs.stdenvNoCC.mkDerivation {
    pname = "mylar3";
    version = "0.8.3";
    src = pkgs.fetchFromGitHub {
      owner = "mylar3";
      repo = "mylar3";
      rev = "cdc94a44425b6f3f9cdb9b6e5f9d88ae2fee3316";
      hash = "sha256-TyawpjRbF5ux7hmccB7/hqADIEPNGv4OLOW0/amVXbQ=";
    };
    nativeBuildInputs = [pkgs.makeWrapper];
    postPatch = ''
      substituteInPlace requirements.txt \
        --replace-fail 'user_agent2>=2021.12.11' '# unused by Mylar3 runtime'
    '';
    installPhase = ''
      runHook preInstall
      mkdir -p "$out/share/mylar3" "$out/bin"
      cp -R . "$out/share/mylar3/"
      rm -rf "$out/share/mylar3/lib/natsort"
      makeWrapper ${mylarPython}/bin/python3 "$out/bin/mylar3" \
        --add-flags "$out/share/mylar3/Mylar.py"
      runHook postInstall
    '';
    doInstallCheck = true;
    installCheckPhase = ''
      runHook preInstallCheck
      ${pkgs.coreutils}/bin/env -u PYTHONPATH ${mylarPython}/bin/python3 -c 'import PIL._imaging'
      runHook postInstallCheck
    '';
    meta = {
      description = "Automated comic book library manager";
      license = lib.licenses.gpl3Plus;
      mainProgram = "mylar3";
      platforms = lib.platforms.linux;
    };
  };
  cfg = config.services.mylar3;
  dataDir = cfg.dataDir;
  stagingRoot = "/srv/media/.arr-staging";
  healthCheck = pkgs.writeShellScript "mylar3-health-check" ''
    set -eu
    for attempt in {1..30}; do
      if ${pkgs.curl}/bin/curl --fail --silent --max-time 1 http://127.0.0.1:${toString cfg.port}/ >/dev/null; then
        exit 0
      fi
      sleep 1
    done
    echo "Mylar3 did not become healthy" >&2
    exit 1
  '';
in {
  options.services.mylar3 = {
    enable = lib.mkEnableOption "Mylar3 comic book library manager";
    package = lib.mkOption {
      type = lib.types.package;
      default = mylar3Package;
      description = "Mylar3 package built from the pinned upstream release.";
    };
    port = lib.mkOption {
      type = lib.types.port;
      default = 8090;
      description = "Port used by the Mylar3 web service.";
    };
    dataDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/mylar3";
      description = "Directory where Mylar3 stores its configuration and database.";
    };
    manageSettingsFile = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Overlay declared Mylar3 settings onto the runtime config.ini before startup.
        Disable temporarily when performing Mylar3's one-time root-path migration
        from an imported backup.
      '';
    };
    settings = lib.mkOption {
      type = lib.types.attrsOf (lib.types.attrsOf (lib.types.oneOf [
        lib.types.str
        lib.types.bool
        lib.types.int
        (lib.types.submodule {
          options.secret = lib.mkOption {
            type = lib.types.pathWith {
              inStore = false;
              absolute = true;
            };
            description = "Runtime file containing a secret setting value.";
          };
        })
      ]));
      default = {};
      description = ''
        Mylar3 INI settings, keyed by section and option. Declared values are
        overlaid on existing configuration before startup; unspecified settings
        remain untouched. Put sensitive values in a runtime secret file using
        `{ secret = /run/secrets/path; }`.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    users.users.mylar3 = {
      isSystemUser = true;
      group = "users";
      home = dataDir;
      createHome = false;
    };

    systemd.services.mylar3 = {
      description = "Mylar3 comic book library manager";
      wantedBy = ["multi-user.target"];
      after = ["network.target" "zfs-mount.service" "media-library-folders.service" "media-management-roots.service"];
      requires = ["media-library-folders.service" "media-management-roots.service"];
      unitConfig = {
        ConditionPathIsMountPoint = "/srv/media";
        RequiresMountsFor = [dataDir "/srv/media"];
      };
      serviceConfig = {
        Type = "simple";
        User = "mylar3";
        Group = "users";
        WorkingDirectory = dataDir;
        StateDirectory = "mylar3";
        StateDirectoryMode = "0750";
        ExecStart = utils.escapeSystemdExecArgs [
          (lib.getExe cfg.package)
          "--nolaunch"
          "--quiet"
          "--datadir=${dataDir}"
          "--port"
          (toString cfg.port)
        ];
        ExecStartPost = "${healthCheck}";
        Restart = "on-failure";
        UMask = "0002";
        CapabilityBoundingSet = "";
        NoNewPrivileges = true;
        PrivateTmp = true;
        PrivateDevices = true;
        ProtectHome = true;
        ProtectSystem = "strict";
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        RestrictSUIDSGID = true;
        LockPersonality = true;
        RestrictAddressFamilies = ["AF_INET" "AF_INET6" "AF_UNIX"];
        ReadWritePaths = [dataDir "/srv/media/comics" stagingRoot];
      };
    };
  };
}
