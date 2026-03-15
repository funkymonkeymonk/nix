# matrix.nix - Matrix Synapse Server MicroVM
# Self-hosted Matrix homeserver with Element Web client
# Uses official nixpkgs module with Opnix for secrets
# Environment files are generated from individual secrets at runtime
# https://github.com/element-hq/synapse
{
  config,
  lib,
  pkgs,
  ...
}: let
  # Configuration
  serverName = "matrix.local";
  baseUrl = "https://${serverName}";
  matrixPort = 8008;
in {
  networking.hostName = "matrix";

  # Disable auto-upgrade for microvm
  system.autoUpgrade.enable = lib.mkForce false;

  # Matrix Synapse service using official nixpkgs module
  services.matrix-synapse = {
    enable = true;
    
    # Server configuration
    settings = {
      server_name = serverName;
      public_baseurl = baseUrl;
      
      # Database - use SQLite for simple microvm setup
      database = {
        name = "sqlite3";
        args.database = "/var/lib/matrix-synapse/homeserver.db";
      };
      
      # Listeners
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
      
      # Registration - disabled for private server
      enable_registration = false;
      
      # URLs
      web_client_location = "https://${serverName}/element/";
      
      # Admin contact
      admin_contact = "mailto:admin@${serverName}";
      
      # Rate limiting - relaxed for local use
      rc_message = {
        per_second = 10;
        burst_count = 50;
      };
      
      # Media storage
      max_upload_size = "100M";
      max_image_pixels = "32M";
      
      # Federation - enabled for OpenClaw integration
      federation_domain_whitelist = [];
      
      # App service for OpenClaw bot (will be configured via env file)
      app_service_config_files = [];
    };
    
    # Data directory
    dataDir = "/var/lib/matrix-synapse";
    
    # Extra config files (for secrets)
    extraConfigFiles = [];
  };

  # Script to generate admin-env from individual secrets
  environment.etc."matrix-synapse/generate-admin-env.sh" = {
    text = ''
      #!/bin/bash
      # Generate admin-env file from individual secrets
      ADMIN_PASS=$(cat /run/secrets/matrix-admin-password)
      BOT_PASS=$(cat /run/secrets/matrix-openclaw-password)
      echo "ADMIN_PASSWORD=$ADMIN_PASS"
      echo "OPENCLAW_PASSWORD=$BOT_PASS"
    '';
    mode = "0750";
    user = "root";
    group = "root";
  };

  # Create admin user via systemd service that runs after synapse
  systemd.services.matrix-synapse-create-admin = {
    description = "Create Matrix admin user";
    after = ["matrix-synapse.service" "onepassword-secrets.service"];
    requires = ["matrix-synapse.service"];
    wantedBy = ["multi-user.target"];
    
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      User = "matrix-synapse";
      Group = "matrix-synapse";
    };
    
    # Generate environment file from secrets and create users
    script = ''
      # Generate admin-env from individual secrets
      ADMIN_PASS=$(cat /run/secrets/matrix-admin-password)
      BOT_PASS=$(cat /run/secrets/matrix-openclaw-password)
      
      # Check if admin user exists, create if not
      if ! ${pkgs.matrix-synapse}/bin/synapse_admin -c /var/lib/matrix-synapse/homeserver.yaml list_users 2>/dev/null | grep -q "@admin:matrix.local"; then
        echo "Creating admin user..."
        ${pkgs.matrix-synapse}/bin/synapse_admin -c /var/lib/matrix-synapse/homeserver.yaml \
          register_new_matrix_user \
          --user admin \
          --password "$ADMIN_PASS" \
          --admin \
          2>/dev/null || echo "Admin user may already exist"
      fi
      
      # Create OpenClaw bot user
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

  # Element Web client (optional, served via nginx)
  services.nginx = {
    enable = true;
    recommendedGzipSettings = true;
    recommendedOptimisation = true;
    recommendedProxySettings = true;
    recommendedTlsSettings = false; # No TLS in microvm
    
    virtualHosts.${serverName} = {
      locations."/" = {
        root = pkgs.element-web;
        index = "index.html";
        tryFiles = "$uri $uri/ /index.html";
      };
      
      locations."/_matrix" = {
        proxyPass = "http://127.0.0.1:${toString matrixPort}";
        proxyWebsockets = true;
        extraConfig = ''
          proxy_read_timeout 600;
          client_max_body_size 100M;
        '';
      };
      
      locations."/_synapse/client" = {
        proxyPass = "http://127.0.0.1:${toString matrixPort}";
        proxyWebsockets = true;
      };
    };
  };

  # Element Web configuration
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
      UIFeature.shareSocial = false;
      UIFeature.shareQrCode = false;
      UIFeature.registration = false;
    };
  };

  # Firewall
  networking.firewall = {
    allowedTCPPorts = [
      80      # HTTP (nginx)
      matrixPort      # Matrix client API
      8448    # Matrix federation
    ];
  };

  # Opnix secrets configuration - store individual secrets, generate env files at runtime
  services.onepassword-secrets = {
    enable = true;
    tokenFile = "/etc/opnix-token";
    
    secrets = {
      # Matrix Synapse signing key
      matrixSynapseSigningKey = {
        reference = "op://Homelab/Matrix Synapse/signing-key";
        path = "/var/lib/matrix-synapse/${serverName}.signing.key";
        owner = "matrix-synapse";
        group = "matrix-synapse";
        mode = "0600";
        services = ["matrix-synapse"];
      };
      
      # Matrix Synapse registration shared secret
      matrixSynapseRegistrationSecret = {
        reference = "op://Homelab/Matrix Synapse/registration-shared-secret";
        path = "/var/lib/matrix-synapse/registration_secret";
        owner = "matrix-synapse";
        group = "matrix-synapse";
        mode = "0600";
        services = ["matrix-synapse"];
      };
      
      # Admin password (individual secret - composed into env at runtime)
      matrixAdminPassword = {
        reference = "op://Homelab/Matrix Synapse/admin-password";
        path = "/run/secrets/matrix-admin-password";
        mode = "0600";
        services = ["matrix-synapse-create-admin"];
      };
      
      # OpenClaw bot password (individual secret - composed into env at runtime)
      matrixOpenclawPassword = {
        reference = "op://Homelab/Matrix Synapse/openclaw-password";
        path = "/run/secrets/matrix-openclaw-password";
        mode = "0600";
        services = ["matrix-synapse-create-admin"];
      };
    };
  };

  # Additional packages
  environment.systemPackages = with pkgs; [
    sqlite
    jq
    curl
    matrix-synapse
  ];

  # Root SSH access
  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIIxGvpCUmx1UV3K22/+sWLdRknZmlTmQgckoAUCApF8"
  ];

  # Time zone
  time.timeZone = "America/New_York";

  # System state
  system.stateVersion = "25.05";
}
