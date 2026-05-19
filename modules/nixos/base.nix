# Shared NixOS configuration for all targets
# Configures users from myConfig with NixOS-specific settings and auto-upgrade
{
  config,
  lib,
  pkgs,
  ...
}:
with lib; {
  config = {
    # Configure NixOS-specific user properties from myConfig.users
    users.users = listToAttrs (map (user: {
        inherit (user) name;
        value = {
          isNormalUser = true;
          description = user.fullName;
          extraGroups = ["networkmanager" "wheel"];
        };
      })
      config.myConfig.users);

    # Default user shell (beats NixOS default at mkDefault 1500)
    users.defaultUserShell = mkOverride 1000 pkgs.zsh;

    # Ensure zsh and ghostty terminfo are available system-wide
    environment.systemPackages = [pkgs.zsh pkgs.ghostty];

    # Enable SSH
    services.openssh.enable = true;

    # Auto-upgrade configuration (enabled when flakeUrl is set)
    # Set myConfig.autoUpgrade.flakeUrl in your machine config to enable
    # Example: myConfig.autoUpgrade.flakeUrl = "github:funkymonkeymonk/nix#type-server";
    system.autoUpgrade = mkIf (config.myConfig.autoUpgrade.flakeUrl != "") {
      enable = true;
      flake = config.myConfig.autoUpgrade.flakeUrl;
      # --refresh: always fetch latest flake from remote (no cache)
      # --impure: required when using hardware.facter which reads from /etc
      flags = ["--refresh" "--impure"];
      dates = "02:00";
      randomizedDelaySec = "45min";
    };

    # Shell alias for manual upgrade trigger
    environment.shellAliases = {
      nix-upgrade = "sudo systemctl start nixos-upgrade";
    };

    # Set hostname from /etc/cloud-init.yaml on boot/activation
    # This allows switch-nix to control the hostname via cloud-init format
    systemd.services.set-hostname-from-cloud-init = {
      description = "Set hostname from /etc/cloud-init.yaml";
      wantedBy = ["multi-user.target"];
      after = ["network-pre.target"];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = pkgs.writeShellScript "set-hostname" ''
          if [[ -f /etc/cloud-init.yaml ]]; then
            # Parse hostname from cloud-init YAML
            hostname=$(grep -E '^hostname:' /etc/cloud-init.yaml | head -1 | sed 's/^hostname:[[:space:]]*//' | tr -d '"' | tr -d "'" | tr -d '[:space:]')
            if [[ -n "$hostname" ]]; then
              ${pkgs.hostname}/bin/hostname "$hostname"
              echo "$hostname" > /etc/hostname
              echo "Set hostname to: $hostname"
            fi
          fi
        '';
      };
    };
  };
}
