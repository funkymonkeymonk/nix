{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.myConfig.tailscale;
in {
  options.myConfig.tailscale = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Tailscale VPN with deployment-generated OAuth authentication";
    };
    authKeyTags = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = ["tag:home-lab"];
      description = "Tags assigned to devices authenticated with deployment-generated OAuth auth keys.";
    };
    exitNode = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Advertise this machine as a Tailscale exit node";
    };
    advertiseRoutes = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "Additional routes to advertise (CIDR notation, e.g. [\"10.0.0.0/24\"])";
    };
    serve = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule {
        options = {
          port = lib.mkOption {
            type = lib.types.port;
            description = "Tailnet-only HTTP port to publish for this local service.";
          };
          target = lib.mkOption {
            type = lib.types.str;
            description = "Local HTTP service URL proxied by Tailscale Serve.";
          };
          readinessUrl = lib.mkOption {
            type = lib.types.str;
            description = "Local URL that must be healthy before Tailscale Serve publishes the service.";
          };
        };
      });
      default = {};
      description = "Local services published through Tailscale Serve; mappings are tailnet-only.";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [pkgs.tailscale];
  };
}
