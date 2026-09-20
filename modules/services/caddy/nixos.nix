# Caddy reverse proxy for internal NixOS applications.
{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.myConfig.caddy;

  caddyPackage = pkgs.caddy.withPlugins {
    plugins = ["github.com/caddy-dns/cloudflare@v0.2.4"];
    hash = "sha256-dQvk6ezY6TQ1J7PjhCXnThF/SqVgPwBO8/RXzHCY+js=";
  };

  mkVirtualHost = _name: app: let
    proxyConfig =
      if app.webRoot == null
      then ''
        reverse_proxy ${app.upstream} {
          ${optionalString (app.upstreamTlsSkipVerify && hasPrefix "https://" app.upstream) ''
          transport http {
            tls_insecure_skip_verify
          }
        ''}
        }
      ''
      else ''
        @upstream_api path /transmission/rpc
        handle @upstream_api {
          reverse_proxy ${app.upstream}
        }
        @upstream_web_root path /transmission/web
        redir @upstream_web_root /transmission/web/ 308
        @upstream_web path /transmission/web/*
        handle @upstream_web {
          reverse_proxy ${app.upstream}
        }
        handle {
          rewrite * ${app.webRoot}{uri}
          reverse_proxy ${app.upstream}
        }
      '';
  in {
    name = app.host;
    value = {
      extraConfig = ''
        tls {
          dns cloudflare {env.CLOUDFLARE_API_TOKEN}
          resolvers 1.1.1.1
        }
        @external not remote_ip 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16 100.64.0.0/10 127.0.0.0/8 fd00::/8 ::1
        respond @external 403
        ${proxyConfig}
      '';
    };
  };
in {
  options.myConfig.caddy = {
    enable = mkEnableOption "Caddy internal reverse proxy";

    cloudflareApiTokenPath = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Runtime path containing the Cloudflare API token used for DNS-01 certificates";
    };

    apps = mkOption {
      type = types.attrsOf (types.submodule {
        options = {
          host = mkOption {
            type = types.str;
            description = "Hostname served by Caddy";
          };

          upstream = mkOption {
            type = types.str;
            description = "Upstream URL or address for the application";
          };

          upstreamTlsSkipVerify = mkOption {
            type = types.bool;
            default = false;
            description = "Disable TLS certificate verification for this HTTPS upstream";
          };

          webRoot = mkOption {
            type = types.nullOr types.str;
            default = null;
            description = "Path prefix for applications whose web UI is not served at the upstream root";
          };
        };
      });
      default = {};
      description = "Internal applications exposed through Caddy";
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.cloudflareApiTokenPath != null;
        message = "myConfig.caddy.cloudflareApiTokenPath must be set when Caddy is enabled";
      }
    ];

    services.caddy = {
      enable = true;
      package = mkForce caddyPackage;
      openFirewall = true;
      virtualHosts = mapAttrs' mkVirtualHost cfg.apps;
    };

    networking.firewall.allowedTCPPorts = [80 443];

    systemd.services.caddy-cloudflare-env = {
      description = "Prepare the Caddy Cloudflare API token";
      wantedBy = ["multi-user.target"];
      before = ["caddy.service"];
      after = ["opnix-secrets.service"];
      requires = ["opnix-secrets.service"];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        token_file=${cfg.cloudflareApiTokenPath}
        env_file=/run/caddy/cloudflare.env
        if [ ! -r "$token_file" ]; then
          echo "Cloudflare API token is missing: $token_file" >&2
          exit 1
        fi
        install -d -m 0750 -o caddy -g caddy /run/caddy
        printf 'CLOUDFLARE_API_TOKEN=%s\n' "$(cat "$token_file")" > "$env_file"
        chown caddy:caddy "$env_file"
        chmod 0400 "$env_file"
      '';
    };

    systemd.services.caddy = {
      wants = ["caddy-cloudflare-env.service"];
      after = ["caddy-cloudflare-env.service"];
      serviceConfig.EnvironmentFile = "/run/caddy/cloudflare.env";
    };
  };
}
