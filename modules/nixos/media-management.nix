{
  config,
  lib,
  pkgs,
  ...
}: let
  stagingRoot = "/srv/media/.arr-staging";
  mediaServices = {
    radarr = {
      roots = ["/srv/media/movies"];
      dataDir = config.services.radarr.dataDir;
    };
    sonarr = {
      roots = ["/srv/media/shows"];
      dataDir = config.services.sonarr.dataDir;
    };
    lidarr = {
      roots = ["/srv/media/music"];
      dataDir = config.services.lidarr.dataDir;
    };
    bazarr = {
      roots = ["/srv/media/movies" "/srv/media/shows"];
      dataDir = config.services.bazarr.dataDir;
    };
  };
  mkMediaService = _name: service: {
    after = ["zfs-mount.service" "media-library-folders.service" "media-management-roots.service"];
    requires = ["media-library-folders.service" "media-management-roots.service"];
    unitConfig = {
      ConditionPathIsMountPoint = "/srv/media";
      RequiresMountsFor = ["/srv/media"];
    };
    serviceConfig = {
      Group = "users";
      PrivateTmp = lib.mkDefault true;
      ProtectSystem = lib.mkForce "strict";
      ReadWritePaths = [service.dataDir] ++ service.roots ++ [stagingRoot];
      UMask = lib.mkForce "0002";
    };
  };
  mediaManagerStateDirectories = [
    {
      name = "radarr";
      path = config.services.radarr.dataDir;
    }
    {
      name = "sonarr";
      path = config.services.sonarr.dataDir;
    }
    {
      name = "lidarr";
      path = config.services.lidarr.dataDir;
    }
    {
      name = "bazarr";
      path = config.services.bazarr.dataDir;
    }
  ];
  prepareMediaManagerStateDirectories =
    lib.concatMapStringsSep "\n"
    (directory: "${pkgs.coreutils}/bin/install -d -o ${lib.escapeShellArg directory.name} -g users -m 0750 ${lib.escapeShellArg directory.path}")
    mediaManagerStateDirectories;
  managerPorts = [
    config.services.radarr.settings.server.port
    config.services.sonarr.settings.server.port
    config.services.lidarr.settings.server.port
    config.services.bazarr.settings.general.port
    config.services.mylar3.port
  ];
in {
  imports = [
    ./mylar3.nix
    ./media-app-reconciliation.nix
  ];

  services.radarr = {
    enable = true;
    group = "users";
    openFirewall = false;
    settings.server.bindaddress = "*";
  };
  services.sonarr = {
    enable = true;
    group = "users";
    openFirewall = false;
    settings.server.bindaddress = "*";
  };
  services.lidarr = {
    enable = true;
    group = "users";
    openFirewall = false;
    settings.server.bindaddress = "*";
  };
  services.bazarr = {
    enable = true;
    group = "users";
    openFirewall = false;
    settings.general.port = 6767;
  };
  services.mylar3 = {
    enable = true;
    settings.General.DESTINATION_DIR = "/srv/media/comics";
  };

  myConfig.mediaManagement = {
    radarr.transmission.enable = true;
    sonarr.transmission.enable = true;
    lidarr.transmission.enable = true;
  };

  myConfig.homepage.directLinks = [
    {
      name = "Radarr";
      group = "Media Management";
      href = "http://drlight.uaru-daggertooth.ts.net:${toString config.services.radarr.settings.server.port}";
      description = "Movie library manager";
    }
    {
      name = "Sonarr";
      group = "Media Management";
      href = "http://drlight.uaru-daggertooth.ts.net:${toString config.services.sonarr.settings.server.port}";
      description = "TV series library manager";
    }
    {
      name = "Lidarr";
      group = "Media Management";
      href = "http://drlight.uaru-daggertooth.ts.net:${toString config.services.lidarr.settings.server.port}";
      description = "Music library manager";
    }
    {
      name = "Mylar3";
      group = "Media Management";
      href = "http://drlight.uaru-daggertooth.ts.net:${toString config.services.mylar3.port}";
      description = "Comic book library manager";
    }
    {
      name = "Bazarr";
      group = "Media Management";
      href = "http://drlight.uaru-daggertooth.ts.net:${toString config.services.bazarr.settings.general.port}";
      description = "Subtitle manager";
    }
  ];

  systemd.services = lib.mkMerge [
    {
      media-management-roots = {
        description = "Prepare Drlight Arr staging on the media ZFS dataset";
        wantedBy = ["multi-user.target"];
        after = ["zfs-mount.service"];
        requires = ["zfs-mount.service"];
        before = ["radarr.service" "sonarr.service" "lidarr.service" "mylar3.service" "bazarr.service"];
        unitConfig = {
          ConditionPathIsMountPoint = "/srv/media";
          RequiresMountsFor = ["/srv/media"];
        };
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        script = ''
          ${pkgs.coreutils}/bin/install -d -o root -g users -m 2775 ${stagingRoot}
          ${prepareMediaManagerStateDirectories}
        '';
      };
    }
    (lib.mapAttrs' (name: service: lib.nameValuePair name (mkMediaService name service)) mediaServices)
    {
      bazarr = {
        after = ["radarr.service" "sonarr.service"];
        wants = ["radarr.service" "sonarr.service"];
      };
    }
  ];

  networking.firewall.interfaces."tailscale0".allowedTCPPorts = managerPorts;
}
