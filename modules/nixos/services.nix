{
  config,
  lib,
  pkgs,
  ...
}: {
  # Jellyfin media server
  services.jellyfin = {
    enable = true;
    package = pkgs.unstable.jellyfin;
    openFirewall = true;
  };

  # Linkwarden bookmark manager
  # Note: This would need to be configured based on the actual service setup
  # services.linkwarden = {
  #   enable = true;
  #   # ... configuration
  # };

  # Mealie recipe manager
  services.mealie = {
    enable = true;
    database.createLocally = true;
    port = 9000;
  };

  # Create Docker network for TubeArchivist containers
  systemd.services.create-tubearchivist-network = {
    serviceConfig.Type = "oneshot";
    wantedBy = ["docker-tubearchivist-redis.service" "docker-tubearchivist-es.service"];
    script = ''
      ${pkgs.docker}/bin/docker network ls | grep -q tubearchivist-net || \
      ${pkgs.docker}/bin/docker network create tubearchivist-net
    '';
  };

  # TubeArchivist Docker containers with persistent network
  virtualisation.oci-containers = {
    backend = "docker";
    containers = {
      tubearchivist = {
        image = "bbilly1/tubearchivist:latest";
        ports = ["8000:8000"];
        volumes = [
          "/srv/media/tubearchivist/videos:/youtube"
          "/srv/media/tubearchivist/cache:/cache"
        ];
        environment = {
          ES_URL = "http://tubearchivist-es:9200";
          REDIS_CON = "redis://archivist-redis:6379";
          HOST_UID = "1000";
          HOST_GID = "1000";
          TA_HOST = "http://${config.myConfig.tubearchivist.host}:8000";
          ALLOWED_HOSTS =
            if config.myConfig.tubearchivist.host == "localhost"
            then "localhost,127.0.0.1"
            else "localhost,127.0.0.1,${config.myConfig.tubearchivist.host}";
          TA_USERNAME = config.myConfig.tubearchivist.secrets.username;
          TA_PASSWORD = config.myConfig.tubearchivist.secrets.password;
          ELASTIC_PASSWORD = "tubearchivist";
          TZ = "America/New_York";
        };
        environmentFiles = ["/run/tubearchivist/environment"];
        dependsOn = ["tubearchivist-es" "archivist-redis"];
        extraOptions = ["--network=tubearchivist-net"];
      };

      archivist-redis = {
        image = "redis:alpine";
        volumes = ["/srv/media/tubearchivist/redis:/data"];
        extraOptions = ["--network=tubearchivist-net"];
      };

      tubearchivist-es = {
        image = "bbilly1/tubearchivist-es:latest";
        volumes = ["/srv/media/tubearchivist/es:/usr/share/elasticsearch/data"];
        environment = {
          ELASTIC_PASSWORD = "tubearchivist";
          "ES_JAVA_OPTS" = "-Xms1g -Xmx1g";
          "xpack.security.enabled" = "true";
          "discovery.type" = "single-node";
          "path.repo" = "/usr/share/elasticsearch/data/snapshot";
        };
        extraOptions = ["--network=tubearchivist-net"];
      };
    };
  };
}
