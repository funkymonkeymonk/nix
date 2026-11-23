{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib) mkOption types;

  cfg = config.myConfig.onePacerr;
  user = "onepacerr";
  uid = 1500;
  credentialEnvFile = "/run/onepacerr/credentials.env";
  credentialRenderer = pkgs.writeShellScript "render-onepacerr-credentials" ''
    exec ${pkgs.python3}/bin/python ${./onepacerr-env.py} \
      --username-file /run/secrets/jellyfin-admin-username \
      --password-file /run/secrets/jellyfin-admin-password \
      --output ${lib.escapeShellArg credentialEnvFile}
  '';

  hasVerifiedPaths = cfg.libraryHostPath != null && cfg.libraryContainerPath != null;
  hasVerifiedLibrary = cfg.jellyfinLibraryName != null && cfg.jellyfinLibraryName != "";
  validLibraryPath =
    hasVerifiedPaths
    && lib.hasPrefix "/srv/media/" cfg.libraryHostPath
    && cfg.libraryHostPath != "/srv/media/shows"
    && lib.hasPrefix "/" cfg.libraryContainerPath
    && cfg.libraryContainerPath != "/";
in {
  options.myConfig.onePacerr = {
    enable = lib.mkEnableOption "OnePacerr for the existing Jellyfin library";

    autoStart = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Start OnePacerr automatically. Keep disabled until the Jellyfin admin
        credentials, library identity/path, and a restorable backup are verified.
      '';
    };

    jellyfinLibraryName = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Verified Jellyfin library name containing the existing OnePacerr series.";
    };

    seriesName = mkOption {
      type = types.str;
      default = "One Pace";
      description = "Existing Jellyfin series that OnePacerr may organize.";
    };

    libraryHostPath = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Verified Drlight host path containing only the target OnePacerr series.";
    };

    libraryContainerPath = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Container path corresponding to the target series path reported by Jellyfin.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = validLibraryPath;
        message = "OnePacerr requires a verified series-only host path under /srv/media and an absolute container path.";
      }
      {
        assertion = hasVerifiedLibrary;
        message = "OnePacerr requires the verified Jellyfin library name; do not guess it.";
      }
      {
        assertion = !cfg.autoStart || (config.services.jellyfin.enable && config.myConfig.onepassword.secrets.jellyfinAdminUsername.reference == "Jellyfin/username" && config.myConfig.onepassword.secrets.jellyfinAdminPassword.reference == "Jellyfin/password");
        message = "OnePacerr auto-start requires the existing Jellyfin admin credentials from the default Opnix vault.";
      }
    ];

    users.users.${user} = {
      isSystemUser = true;
      inherit uid;
      group = "users";
    };

    myConfig.onepassword.secrets.jellyfinAdminUsername.services = lib.optional cfg.autoStart "podman-onepacerr";
    myConfig.onepassword.secrets.jellyfinAdminPassword.services = lib.optional cfg.autoStart "podman-onepacerr";

    virtualisation.oci-containers.containers.onepacerr = {
      image = "ghcr.io/eltharynd/onepacerr:v1.8.16";
      autoStart = cfg.autoStart;
      user = "${toString uid}:${toString config.users.groups.users.gid}";
      environmentFiles = [credentialEnvFile];
      environment = {
        JELLYFIN_URL = "http://host.containers.internal:8096";
        JELLYFIN_LIBRARY_NAME = cfg.jellyfinLibraryName;
        LIBRARY_MEDIA_SERVER = "jellyfin";
        LIBRARY_SERIES_NAME = cfg.seriesName;
        LIBRARY_SERIES_FOLDER_NAME = cfg.seriesName;
        LIBRARY_CREATE_SHOW_IF_NOT_FOUND = "false";
        MOUNT_LIBRARY_MEDIA_SERVER = cfg.libraryHostPath;
        MOUNT_LIBRARY_ONEPACERR = cfg.libraryContainerPath;
        PIPELINE_SKIP_DOWNLOADS = "true";
        PIPELINE_SKIP_ORGANIZE_PRESENT_FILES = "false";
        PIPELINE_SKIP_UPDATE_METADATA_PRESENT_FILES = "false";
      };
      volumes = ["${cfg.libraryHostPath}:${cfg.libraryContainerPath}:rw"];
    };

    systemd.services.podman-onepacerr = {
      after = ["opnix-secrets.service" "zfs-mount.service" "jellyfin.service" "jellyfin-admin-auth.service"];
      requires = ["opnix-secrets.service" "zfs-mount.service" "jellyfin.service" "jellyfin-admin-auth.service"];
      unitConfig = {
        ConditionPathIsMountPoint = "/srv/media";
        ConditionPathIsDirectory = cfg.libraryHostPath;
        RequiresMountsFor = [cfg.libraryHostPath];
      };
      serviceConfig.ExecStartPre = lib.mkBefore [credentialRenderer];
    };
  };
}
