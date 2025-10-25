{
  config,
  pkgs,
  ...
}: {
  # Jellyfin media server
  services.jellyfin = {
    enable = true;
    package = pkgs.unstable.jellyfin;
    openFirewall = true;
  };

  # Linkwarden bookmark manager and related systemd configuration
  systemd = {
    services.linkwarden = {
      description = "Linkwarden bookmark manager";
      after = [
        "network.target"
        "postgresql.service"
      ];
      wants = ["postgresql.service"];
      wantedBy = ["multi-user.target"];

      environment = {
        DATABASE_URL = "postgresql://linkwarden@localhost:5432/linkwarden";
        LINKWARDEN_HOST = "127.0.0.1";
        LINKWARDEN_PORT = "3000";
        NEXTAUTH_URL = "https://bookmarks.home.buildingbananas.com";
        NEXTAUTH_SECRET = config.myConfig.secrets.linkwarden.nextAuthSecret;
        STORAGE_FOLDER = "/var/lib/linkwarden";
        LINKWARDEN_CACHE_DIR = "/var/cache/linkwarden";
        NEXT_TELEMETRY_DISABLED = "1";
      };

      serviceConfig = {
        Type = "simple";
        User = "linkwarden";
        Group = "linkwarden";
        WorkingDirectory = "${pkgs.unstable.linkwarden}/share/linkwarden";
        ExecStart = "${pkgs.unstable.linkwarden}/bin/linkwarden";
        Restart = "always";
        RestartSec = "10";

        # Security hardening
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectHome = true;
        ProtectSystem = "strict";
        ReadWritePaths = [
          "/var/lib/linkwarden"
          "/var/cache/linkwarden"
        ];
      };
    };

    services.linkwarden-worker = {
      description = "Linkwarden worker service";
      after = [
        "network.target"
        "postgresql.service"
      ];
      wants = ["postgresql.service"];
      wantedBy = ["multi-user.target"];

      environment = {
        DATABASE_URL = "postgresql://linkwarden@localhost:5432/linkwarden";
        STORAGE_FOLDER = "/var/lib/linkwarden";
        LINKWARDEN_CACHE_DIR = "/var/cache/linkwarden";
        NEXT_TELEMETRY_DISABLED = "1";
      };

      serviceConfig = {
        Type = "simple";
        User = "linkwarden";
        Group = "linkwarden";
        WorkingDirectory = "${pkgs.unstable.linkwarden}/share/linkwarden";
        ExecStart = "${pkgs.unstable.linkwarden}/bin/linkwarden worker";
        Restart = "always";
        RestartSec = "10";

        # Security hardening
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectHome = true;
        ProtectSystem = "strict";
        ReadWritePaths = [
          "/var/lib/linkwarden"
          "/var/cache/linkwarden"
        ];
      };
    };

    tmpfiles.rules = [
      "d /var/lib/linkwarden 0750 linkwarden linkwarden -"
      "d /var/cache/linkwarden 0750 linkwarden linkwarden -"
    ];
  };

  # Create linkwarden user and directories
  users.users.linkwarden = {
    isSystemUser = true;
    group = "linkwarden";
    home = "/var/lib/linkwarden";
    createHome = true;
  };

  users.groups.linkwarden = {};
}
