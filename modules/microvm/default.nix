# MicroVM guest module - runs INSIDE the VM
# Configures: bridge networking, cloud-init consumption, SSH
# Does NOT configure hypervisor, interfaces, or shares (those are host-side)
{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cloudInitDir = "/etc/cloud-init";
in {
  imports = [
    ../nixos/ghostty-terminfo.nix
  ];

  # Guest networking — bridge subnet
  networking = {
    hostName = lib.mkDefault "microvm";
    useDHCP = false;
    firewall.enable = false;

    interfaces.eth0 = {
      useDHCP = false;
      ipv4.addresses = lib.mkIf (config.myConfig.microvm.ipAddress != null) [
        {
          address = config.myConfig.microvm.ipAddress;
          prefixLength = 24;
        }
      ];
    };

    defaultGateway = lib.mkIf (config.myConfig.microvm.gateway != null) {
      address = config.myConfig.microvm.gateway;
      interface = "eth0";
    };

    nameservers = lib.mkDefault ["192.168.83.1"];
  };

  # Cloud-init: apply hostname from mounted share
  systemd.services.apply-cloud-init = {
    description = "Apply cloud-init configuration from host";
    wantedBy = ["multi-user.target"];
    after = ["network-pre.target"];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      HOSTNAME="${config.networking.hostName}"
      CI_FILE="${cloudInitDir}/$HOSTNAME.yaml"

      if [[ -f "$CI_FILE" ]]; then
        ci_hostname=$(grep -E '^hostname:' "$CI_FILE" | head -1 | sed 's/^hostname:[[:space:]]*//' | tr -d '"' | tr -d "'" | tr -d '[:space:]')
        if [[ -n "$ci_hostname" ]]; then
          ${pkgs.hostname}/bin/hostname "$ci_hostname"
          echo "$ci_hostname" > /etc/hostname
          echo "Applied hostname from cloud-init: $ci_hostname"
        fi
        echo "Cloud-init applied from $CI_FILE"
      else
        echo "No cloud-init config found at $CI_FILE"
      fi
    '';
  };

  # Enable SSH for management with agent forwarding support
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "prohibit-password";
      PasswordAuthentication = false;
      AllowAgentForwarding = true; # Enable SSH agent forwarding for 1Password
    };
  };

  environment.systemPackages = with pkgs; [
    vim
    git
    htop
    curl
  ];

  system.stateVersion = "25.05";
}
