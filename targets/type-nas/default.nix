# type-nas - Network Attached Storage with document management
# Cattle configuration: ZFS storage + paperless-ngx for document archival
{pkgs, ...}: {
  # ZFS support
  boot.supportedFilesystems = ["zfs"];
  boot.zfs.forceImportRoot = false;

  # ZFS kernel module
  boot.kernelModules = ["zfs"];

  # Paperless-ngx document management
  services.paperless = {
    enable = true;
    address = "0.0.0.0";
    port = 28981;
    dataDir = "/var/lib/paperless";

    # Configure with sensible defaults
    settings = {
      PAPERLESS_OCR_LANGUAGE = "eng";
      PAPERLESS_CONSUMER_RECURSIVE = "true";
      PAPERLESS_CONSUMER_SUBDIRS_AS_TAGS = "true";
    };
  };

  # Ensure paperless can consume from a watched directory
  # Note: ZFS dataset handles main storage, this creates the consume subdirectory
  systemd.tmpfiles.rules = [
    "d /var/lib/paperless/consume 0755 paperless paperless -"
  ];

  # Open firewall for paperless web UI
  networking.firewall.allowedTCPPorts = [28981];

  # ZFS maintenance services
  services.zfs.autoScrub.enable = true;
  services.sanoid = {
    enable = true;
    templates = {
      # Daily snapshots, keep for a month
      daily = {
        hourly = 24;
        daily = 30;
        monthly = 3;
        autosnap = true;
        autoprune = true;
      };
    };
    datasets = {
      "tank/paperless" = {
        useTemplate = ["daily"];
      };
      "tank/data" = {
        useTemplate = ["daily"];
      };
    };
  };

  environment.systemPackages = with pkgs; [
    vim
    htop
    curl
    zfs
    sanoid
    parted
  ];
}
