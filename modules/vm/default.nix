{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.myConfig.vm;
in {
  options.myConfig.vm = {
    enable = mkEnableOption "VM configuration for testing";

    memorySize = mkOption {
      type = types.int;
      default = 2048;
      description = "Memory size in MB for the VM";
    };

    cores = mkOption {
      type = types.int;
      default = 2;
      description = "Number of CPU cores for the VM";
    };

    graphics = mkOption {
      type = types.bool;
      default = false;
      description = "Enable graphics for the VM";
    };

    forwardPorts = mkOption {
      type = types.listOf (types.submodule {
        options = {
          from = types.str;
          host.port = types.int;
          guest.port = types.int;
        };
      });
      default = [];
      description = "Ports to forward from host to guest";
    };
  };

  config = mkIf cfg.enable {
    # VM-specific configuration that only applies when building with build-vm
    virtualisation.vmVariant = {
      # Override virtualisation settings for VM builds
      virtualisation = {
        inherit (cfg) memorySize cores graphics;

        # Default port forwarding for SSH
        forwardPorts =
          cfg.forwardPorts
          ++ [
            {
              from = "host";
              host.port = 2222;
              guest.port = 22;
            }
          ];

        # Optimize for CI/CD environments
        diskSize = mkDefault 10240; # 10GB
      };

      # Ensure SSH is enabled for testing
      services.openssh = {
        enable = true;
        settings = {
          PasswordAuthentication = true;
          PermitRootLogin = "yes";
        };
      };

      # Create test user if not exists
      users.users.test = mkIf (!config.users.users ? test) {
        isNormalUser = true;
        password = "test";
        extraGroups = ["wheel"];
      };

      # Disable firewall for easier testing
      networking.firewall.enable = mkDefault false;

      # Add basic testing tools
      environment.systemPackages = with pkgs; [
        curl
        wget
        vim
        htop
        git
      ];
    };
  };
}
