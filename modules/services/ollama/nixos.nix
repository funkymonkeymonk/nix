# Ollama service module for NixOS (Linux)
#
# Uses systemd to manage Ollama as a system service.
# Imports shared configuration from common.nix.
{
  config,
  lib,
  ...
}:
with lib; let
  cfg = config.myConfig.ollama;

  # Common values are exposed via config._ollamaCommon from common.nix
  inherit (config._ollamaCommon) serviceEnvironment ollamaStartScript pathEnv packages;
in {
  imports = [./common.nix];

  config = mkIf cfg.enable {
    environment.systemPackages = packages;

    systemd.services.ollama = {
      description = "Ollama Local LLM Server";
      wantedBy = ["multi-user.target"];
      after = ["network-online.target"];
      wants = ["network-online.target"];

      serviceConfig = {
        Type = "simple";
        ExecStart = "${ollamaStartScript}";
        Restart = "on-failure";
        RestartSec = "5s";

        # Environment variables
        Environment = mapAttrsToList (n: v: "${n}=${v}") (serviceEnvironment
          // {
            PATH = pathEnv;
          });

        # Environment file support
        EnvironmentFile = mkIf (cfg.environmentFile != null) cfg.environmentFile;

        # Basic hardening
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = "read-only";
        ReadWritePaths = [
          "/var/lib/ollama"
          "/tmp"
        ];
      };
    };

    # Create state directory
    systemd.tmpfiles.rules = [
      "d /var/lib/ollama 0755 root root -"
    ];

    # Open firewall if binding to non-localhost
    networking.firewall.allowedTCPPorts =
      mkIf (cfg.host != "127.0.0.1") [cfg.port];
  };
}
