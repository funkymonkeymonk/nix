# matrix.nix - Matrix Synapse Server MicroVM
# Secrets are staged by the host via cloud-init (no Opnix in guest)
# https://github.com/element-hq/synapse
{
  lib,
  pkgs,
  ...
}: let
  serverName = "matrix.local";
  baseUrl = "https://${serverName}";
  matrixPort = 8008;
in {
  networking.hostName = "matrix";

  system.autoUpgrade.enable = lib.mkForce false;

  # Microvm-specific network config
  myConfig.microvm = {
    enable = true;
    ipAddress = "192.168.83.15";
    gateway = "192.168.83.1";
  };

  services.matrix-synapse = {
    enable = true;

    settings = {
      server_name = serverName;
      public_baseurl = baseUrl;

      database = {
        name = "sqlite3";
        args.database = "/var/lib/matrix-synapse/homeserver.db";
      };

      listeners = [
        {
          port = matrixPort;
          bind_addresses = ["0.0.0.0"];
          type = "http";
          tls = false;
          x_forwarded = false;
          resources = [
            {
              names = ["client" "federation"];
              compress = false;
            }
          ];
        }
      ];

      enable_registration = false;

      web_client_location = "https://${serverName}/element/";
      admin_contact = "mailto:admin@${serverName}";

      rc_message = {
        per_second = 10;
        burst_count = 50;
      };

      max_upload_size = "100M";
      max_image_pixels = "32M";

      federation_domain_whitelist = [];
      app_service_config_files = [];
    };

    dataDir = "/var/lib/matrix-synapse";
    extraConfigFiles = [];
  };

  # Create admin user via systemd service
  systemd.services.matrix-synapse-create-admin = {
    description = "Create Matrix admin user";
    after = ["matrix-synapse.service"];
    requires = ["matrix-synapse.service"];
    wantedBy = ["multi-user.target"];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      User = "matrix-synapse";
      Group = "matrix-synapse";
    };

    script = ''
      ADMIN_PASS=$(cat /run/secrets/matrix-admin-password 2>/dev/null || echo "admin_placeholder")
      BOT_PASS=$(cat /run/secrets/matrix-openclaw-password 2>/dev/null || echo "bot_placeholder")

      if ! ${pkgs.matrix-synapse}/bin/synapse_admin -c /var/lib/matrix-synapse/homeserver.yaml list_users 2>/dev/null | grep -q "@admin:matrix.local"; then
        echo "Creating admin user..."
        ${pkgs.matrix-synapse}/bin/synapse_admin -c /var/lib/matrix-synapse/homeserver.yaml \
          register_new_matrix_user \
          --user admin \
          --password "$ADMIN_PASS" \
          --admin \
          2>/dev/null || echo "Admin user may already exist"
      fi

      if ! ${pkgs.matrix-synapse}/bin/synapse_admin -c /var/lib/matrix-synapse/homeserver.yaml list_users 2>/dev/null | grep -q "@openclaw:matrix.local"; then
        echo "Creating OpenClaw bot user..."
        ${pkgs.matrix-synapse}/bin/synapse_admin -c /var/lib/matrix-synapse/homeserver.yaml \
          register_new_matrix_user \
          --user openclaw \
          --password "$BOT_PASS" \
          --no-admin \
          2>/dev/null || echo "OpenClaw user may already exist"
      fi
    '';
  };

  services.nginx = {
    enable = true;
    recommendedGzipSettings = true;
    recommendedOptimisation = true;
    recommendedProxySettings = true;
    recommendedTlsSettings = false;

    virtualHosts.${serverName} = {
      locations = {
        "/" = {
          root = pkgs.element-web;
          index = "index.html";
          tryFiles = "$uri $uri/ /index.html";
        };
        "/_matrix" = {
          proxyPass = "http://127.0.0.1:${toString matrixPort}";
          proxyWebsockets = true;
          extraConfig = ''
            proxy_read_timeout 600;
            client_max_body_size 100M;
          '';
        };
        "/_synapse/client" = {
          proxyPass = "http://127.0.0.1:${toString matrixPort}";
          proxyWebsockets = true;
        };
      };
    };
  };

  environment.etc."element-web/config.json".text = builtins.toJSON {
    default_server_config = {
      "m.homeserver" = {
        base_url = "http://localhost:${toString matrixPort}";
        server_name = serverName;
      };
      "m.identity_server" = {
        base_url = "https://vector.im";
      };
    };
    disable_custom_urls = false;
    disable_guests = true;
    disable_login_language_selector = false;
    disable_3pid_login = true;
    brand = "Element";
    integrations_ui_url = "https://scalar.vector.im/";
    integrations_rest_url = "https://scalar.vector.im/api";
    integrations_widgets_urls = [
      "https://scalar.vector.im/_matrix/integrations/v1"
      "https://scalar.vector.im/api"
      "https://scalar-staging.vector.im/_matrix/integrations/v1"
      "https://scalar-staging.vector.im/api"
      "https://scalar-staging.riot.im/scalar/api"
    ];
    default_widget_container_height = 280;
    room_directory = {
      servers = [serverName "matrix.org" "gitter.im"];
    };
    enable_presence_by_hs_url = {
      "https://matrix.org" = false;
      "https://matrix-client.matrix.org" = false;
    };
    features = {};
    setting_defaults = {
      breadcrumbs = true;
      UIFeature = {
        shareSocial = false;
        shareQrCode = false;
        registration = false;
      };
    };
  };

  networking.firewall = {
    allowedTCPPorts = [
      80
      matrixPort
      8448
    ];
  };

  # Opnix secrets configuration
  services.onepassword-secrets = {
    enable = true;
    tokenFile = "/etc/opnix-token";

    secrets = {
      matrixSynapseSigningKey = {
        reference = "op://Homelab/Matrix Synapse/signing-key";
        path = "/var/lib/matrix-synapse/${serverName}.signing.key";
        owner = "matrix-synapse";
        group = "matrix-synapse";
        mode = "0600";
        services = ["matrix-synapse"];
      };

      matrixSynapseRegistrationSecret = {
        reference = "op://Homelab/Matrix Synapse/registration-shared-secret";
        path = "/var/lib/matrix-synapse/registration_secret";
        owner = "matrix-synapse";
        group = "matrix-synapse";
        mode = "0600";
        services = ["matrix-synapse"];
      };

      matrixAdminPassword = {
        reference = "op://Homelab/Matrix Synapse/admin-password";
        path = "/run/secrets/matrix-admin-password";
        mode = "0600";
        services = ["matrix-synapse-create-admin"];
      };

      matrixOpenclawPassword = {
        reference = "op://Homelab/Matrix Synapse/openclaw-password";
        path = "/run/secrets/matrix-openclaw-password";
        mode = "0600";
        services = ["matrix-synapse-create-admin"];
      };
    };
  };

  environment.systemPackages = with pkgs; [
    sqlite
    jq
    curl
    matrix-synapse
  ];

  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIIxGvpCUmx1UV3K22/+sWLdRknZmlTmQgckoAUCApF8"
  ];

  time.timeZone = "America/New_York";
  system.stateVersion = "25.05";
}
