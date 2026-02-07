{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.virtualisation.colima;
in {
  options.virtualisation.colima = {
    enable = mkEnableOption "Colima container runtime";

    cpu = mkOption {
      type = types.int;
      default = 2;
      description = "Number of CPUs to allocate to Colima";
    };

    memory = mkOption {
      type = types.int;
      default = 4096;
      description = "Memory in MB to allocate to Colima";
    };

    disk = mkOption {
      type = types.int;
      default = 60;
      description = "Disk size in GB to allocate to Colima";
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      colima
      docker
      docker-compose
    ];

    # Colima systemd service
    systemd.services.colima = {
      description = "Colima container runtime service";
      after = ["network-online.target"];
      wants = ["network-online.target"];
      wantedBy = ["multi-user.target"];

      serviceConfig = {
        Type = "simple";
        ExecStart = "${pkgs.colima}/bin/colima start --cpu ${toString cfg.cpu} --memory ${toString cfg.memory} --disk ${toString cfg.disk}";
        ExecStop = "${pkgs.colima}/bin/colima stop";
        ExecReload = "${pkgs.colima}/bin/colima restart";
        Restart = "on-failure";
        RestartSec = "5s";
        User = "root";
        Group = "docker";
      };

      environment = {
        COLIMA_HOME = "/var/lib/colima";
      };
    };

    # Docker group for users to access Docker
    users.groups.docker = {};

    # Create Colima data directory
    systemd.tmpfiles.rules = [
      "d /var/lib/colima 0755 root docker -"
    ];
  };
}
