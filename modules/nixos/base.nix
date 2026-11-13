# Shared NixOS configuration for all targets
# Configures users from myConfig with NixOS-specific settings and auto-upgrade
{
  config,
  lib,
  options,
  pkgs,
  ...
}:
with lib; let
  hasSystemd = builtins.hasAttr "systemd" options;
in {
  imports = [./tailscale.nix];

  options.myConfig.autoUpgrade.flakeUrl = mkOption {
    type = types.str;
    default = "";
    description = ''
      GitHub flake URL for auto-upgrade (e.g., 'github:funkymonkeymonk/nix#type-server'). Set this to enable auto-upgrade on NixOS machines.
      Creating /var/lib/nixos-upgrade.disabled pauses scheduled upgrades on that host; manual upgrades remain available.
    '';
  };

  config =
    {
      # Configure NixOS-specific user properties from myConfig.users
      users.users = listToAttrs (map (user: {
          inherit (user) name;
          value = {
            isNormalUser = true;
            description = user.fullName;
            extraGroups = ["networkmanager" "wheel" "onepassword-secrets" "docker"];
            shell = pkgs.zsh;
          };
        })
        config.myConfig.users);

      # Enable Docker for NixOS systems using the shared base configuration.
      virtualisation.docker.enable = true;

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
    }
    // optionalAttrs hasSystemd {
      systemd = mkIf (config.myConfig.autoUpgrade.flakeUrl != "") {
        # Check the persistent sentinel each time the schedule fires. The timer
        # starts this guard service, which leaves manual nixos-upgrade starts alone.
        services.nixos-upgrade-scheduled = {
          description = "Run scheduled NixOS upgrades unless disabled on this host";
          unitConfig.ConditionPathExists = "!/var/lib/nixos-upgrade.disabled";
          serviceConfig.Type = "oneshot";
          script = ''
            # A switch can start this guard while an upgrade or another switch is running.
            # Skip duplicate work so activation does not wait on itself or launch a competing rebuild.
            for unit in nixos-upgrade.service nixos-rebuild-switch-to-configuration.service; do
              unit_state=$(${pkgs.systemd}/bin/systemctl show --property=ActiveState --value "$unit")
              case "$unit_state" in
                active|activating|deactivating|reloading)
                  echo "Skipping scheduled upgrade; $unit is $unit_state"
                  exit 0
                  ;;
              esac
            done
            exec ${pkgs.systemd}/bin/systemctl start nixos-upgrade.service
          '';
        };
        timers.nixos-upgrade.timerConfig.Unit = "nixos-upgrade-scheduled.service";
      };
    };
}
