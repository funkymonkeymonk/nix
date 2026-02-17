{
  lib,
  pkgs,
  config,
  ...
}: {
  options.services.o11y = {
    enable = lib.mkEnableOption "Observability stack (LGTM)";

    grafanaPasswordFile = lib.mkOption {
      type = lib.types.path;
      description = "Path to file containing Grafana admin password";
    };
  };

  config = lib.mkIf config.services.o11y.enable {
    environment = lib.mkMerge [
      {
        systemPackages = with pkgs; [
          colima
          docker-compose
        ];
      }
      {
        etc."o11y/docker-compose.yml".text = ''
          services:
            loki:
              image: grafana/loki:3.2.0
              ports:
                - "3100:3100"
              volumes:
                - o11y_loki_data:/loki
              command: >
                -config.file=/etc/loki/local-config.yaml
                -auth.enabled=true
                -auth.basic_users_file=/etc/loki/users.ini
              restart: unless-stopped
              secrets:
                - loki_password

            grafana:
              image: grafana/grafana:11.4.0
              ports:
                - "3000:3000"
              environment:
                - GF_SECURITY_ADMIN_PASSWORD_FILE=/run/secrets/grafana-admin-password
                - GF_USERS_ALLOW_SIGN_UP=false
              volumes:
                - o11y_grafana_data:/var/lib/grafana
              restart: unless-stopped
              secrets:
                - grafana_admin_password
              depends_on:
                - loki

          secrets:
            grafana_admin_password:
              file: /run/secrets/grafana-admin-password
            loki_password:
              file: /run/secrets/loki-password

          volumes:
            o11y_loki_data:
            o11y_grafana_data:
        '';

        etc."o11y/promtail-config.yml".text = ''
          server:
            http_listen_port: 9080
            grpc_listen_port: 0

          positions:
            filename: /tmp/promtail-positions.yaml

          clients:
            - url: http://localhost:3100/loki/api/v1/push
              # Authenticate to Loki to prevent unauthorized log injection
              basic_auth:
                username: promtail
                password_file: /run/secrets/loki-password

          scrape_configs:
            - job_name: system
              static_configs:
                - targets:
                    - localhost
                  labels:
                    job: system
                    __path__: /var/log/**/*.log
        '';
      }
      {
        variables = {
          O11Y_LOKI_URL = "http://localhost:3100";
          O11Y_GRAFANA_URL = "http://localhost:3000";
        };
      }
    ];

    launchd.daemons.o11y = {
      serviceConfig = {
        Label = "com.o11y.service";
        ProgramArguments = [
          "/usr/bin/env"
          "bash"
          "-c"
          "cd /etc/o11y && docker-compose up"
        ];
        RunAtLoad = true;
        KeepAlive = true;
        StandardOutPath = "/var/log/o11y.log";
        StandardErrorPath = "/var/log/o11y.log";
      };
    };
  };
}
