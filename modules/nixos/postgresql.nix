# PostgreSQL service module for NixOS (Linux)
#
# Uses NixOS's native services.postgresql module
{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.myConfig.postgresql;
in {
  config = mkIf cfg.enable {
    # Use NixOS's native PostgreSQL service
    services.postgresql = {
      enable = true;
      package =
        if cfg.package != null
        then cfg.package
        else pkgs.postgresql_17;
      enableTCPIP = cfg.enableTCPIP;
      port = cfg.port;

      # Set data directory if specified
      dataDir = mkIf (cfg.dataDir != null) cfg.dataDir;

      # Create databases
      ensureDatabases = cfg.databases;

      # Create users
      ensureUsers =
        map (user: {
          name = user.name;
          ensureDBOwnership = user.ensureDBOwnership;
        })
        cfg.users;

      # Allow local connections with peer auth, and TCP with md5
      authentication = pkgs.lib.mkOverride 10 ''
        # TYPE  DATABASE        USER            ADDRESS                 METHOD
        local   all             all                                     peer
        host    all             all             127.0.0.1/32            md5
        host    all             all             ::1/128                 md5
      '';
    };

    # Add PostgreSQL client tools to system packages
    environment.systemPackages = [
      (
        if cfg.package != null
        then cfg.package
        else pkgs.postgresql_17
      )
    ];

    # Open firewall if TCP/IP is enabled
    networking.firewall.allowedTCPPorts = mkIf cfg.enableTCPIP [cfg.port];

    # Shell aliases for convenience
    environment.shellAliases = {
      pg-status = "pg_isready -h localhost -p ${toString cfg.port}";
      pg-logs = "journalctl -u postgresql -f";
    };
  };
}
