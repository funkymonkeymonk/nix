{
  config,
  lib,
  options,
  pkgs,
  ...
}: let
  cfg = config.myConfig.mediaConfig;
  mediaLibraryPaths = map (name: "/srv/media/${name}") [
    "audiobooks"
    "books"
    "comics"
    "movies"
    "music"
    "shows"
  ];
in {
  options.myConfig.mediaConfig.enable = lib.mkEnableOption "media services";

  config = lib.mkIf cfg.enable {
    services.jellyfin.enable = true;
    services.jellyfin.openFirewall = false;

    services.prometheus.scrapeConfigs = lib.mkIf (builtins.hasAttr "prometheus" options.services && config.services.prometheus.enable) [
      {
        job_name = "jellyfin";
        static_configs = [{targets = ["127.0.0.1:8096"];}];
      }
    ];

    systemd.services.jellyfin.preStart = ''
      ${pkgs.python3}/bin/python - <<'PY'
      import os
      import xml.etree.ElementTree as ET

      path = os.path.join(${lib.escapeShellArg config.services.jellyfin.configDir}, "system.xml")
      try:
          tree = ET.parse(path)
          root = tree.getroot()
      except FileNotFoundError:
          root = ET.Element("SystemConfiguration")
          tree = ET.ElementTree(root)

      metrics = root.find("EnableMetrics")
      if metrics is None:
          metrics = ET.SubElement(root, "EnableMetrics")
      metrics.text = "true"
      tree.write(path, encoding="utf-8", xml_declaration=True)
      PY
    '';

    networking.firewall = {
      allowedTCPPorts = [8096];
      allowedUDPPorts = [7359];
    };

    systemd.services.jellyfin = {
      after = ["zfs-mount.service" "media-library-folders.service"];
      requires = ["media-library-folders.service"];
      unitConfig = {
        ConditionPathIsMountPoint = "/srv/media";
        RequiresMountsFor = ["/srv/media"];
      };
    };

    systemd.services.media-library-folders = {
      description = "Create media library roots on the ZFS dataset";
      wantedBy = ["multi-user.target"];
      requires = ["zfs-mount.service"];
      after = ["zfs-mount.service"];
      before = ["jellyfin.service"];
      unitConfig.ConditionPathIsMountPoint = "/srv/media";
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        set -eu
        ${lib.concatMapStringsSep "\n" (path: ''
            install -d -o root -g users -m 2775 ${lib.escapeShellArg path}
          '')
          mediaLibraryPaths}
      '';
    };
  };
}
