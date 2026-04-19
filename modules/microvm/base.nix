# MicroVM Base Configuration
# This is the foundation that ALL MicroVMs inherit from
# Per-VM customizations are overlays on top of this
{
  config,
  lib,
  pkgs,
  ...
}: {
  # Essential MicroVM guest configuration
  imports = [
    ../nixos/ghostty-terminfo.nix
  ];

  # Standard networking setup
  networking = {
    hostName = lib.mkDefault "microvm";
    useDHCP = false;
    firewall.enable = false;
    nameservers = lib.mkDefault ["192.168.83.1"];
  };

  # Guest networking - applied via myConfig.microvm.ipAddress in each VM
  networking.interfaces.eth0 = {
    useDHCP = false;
  };

  # SSH for management
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "prohibit-password";
      PasswordAuthentication = false;
    };
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
      CI_FILE="/etc/cloud-init/$HOSTNAME.yaml"

      if [[ -f "$CI_FILE" ]]; then
        ci_hostname=$(grep -E '^hostname:' "$CI_FILE" | head -1 | sed 's/^hostname:[[:space:]]*//' | tr -d '"' | tr -d "'" | tr -d '[:space:]')
        if [[ -n "$ci_hostname" ]]; then
          ${pkgs.hostname}/bin/hostname "$ci_hostname"
          echo "$ci_hostname" > /etc/hostname
          echo "Applied hostname from cloud-init: $ci_hostname"
        fi
      fi
    '';
  };

  # Base system packages available in all MicroVMs
  environment.systemPackages = with pkgs; [
    vim
    git
    htop
    curl
    jq
  ];

  # Disable auto-upgrade in MicroVMs (host controls updates)
  system.autoUpgrade.enable = lib.mkForce false;

  system.stateVersion = "25.05";
}
