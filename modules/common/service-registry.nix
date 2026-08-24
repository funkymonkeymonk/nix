# myConfig.serviceRegistry option — owned here, populated by each service
# module (bifrost, caddy, vane, searxng, node-exporter, prometheus, vllm-mlx)
# via commonLib.mkServiceRegistry, and consumed here for port-conflict
# detection across all enabled services.
{
  config,
  lib,
  options,
  ...
}: {
  options.myConfig.serviceRegistry = lib.mkOption {
    type = lib.types.attrsOf (lib.types.submodule {
      options = {
        name = lib.mkOption {
          type = lib.types.str;
          description = "Human-readable service name";
        };
        port = lib.mkOption {
          type = lib.types.port;
          description = "Port the service binds to";
        };
        launchdLabel = lib.mkOption {
          type = lib.types.str;
          description = "launchd service label (e.g. org.vllm-mlx.server)";
        };
        errorLog = lib.mkOption {
          type = lib.types.str;
          description = "Path to stderr log for port conflict detection";
        };
      };
    });
    default = {};
    description = "Registry of all managed services for port conflict detection and readiness verification";
  };

  # Port conflict prevention — generic check from service registry
  config = let
    services = builtins.attrValues config.myConfig.serviceRegistry;
    uniquePorts = lib.unique (map (s: s.port) services);
    conflictPorts =
      lib.filter (
        p:
          (builtins.length (builtins.filter (s: s.port == p) services)) > 1
      )
      uniquePorts;
  in
    lib.optionalAttrs (builtins.hasAttr "assertions" options) {
      assertions = [
        {
          assertion = conflictPorts == [];
          message = ''
            Port conflicts detected between enabled services:
            ${builtins.concatStringsSep "\n" (map (
                p: "  port ${toString p}: ${builtins.concatStringsSep ", " (map (s: s.name) (builtins.filter (s: s.port == p) services))}"
              )
              conflictPorts)}

            Each service must use a unique port. Change one of the conflicting service's port options.
          '';
        }
      ];
    };
}
