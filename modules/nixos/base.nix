# Shared NixOS configuration for all targets
# Configures users from myConfig with NixOS-specific settings and auto-upgrade
{
  config,
  lib,
  pkgs,
  ...
}:
with lib; {
  options.myConfig.autoUpgrade.flakeUrl = mkOption {
    type = types.str;
    default = "";
    description = "GitHub flake URL for auto-upgrade (e.g., 'github:funkymonkeymonk/nix#type-server'). Set this to enable auto-upgrade on NixOS machines.";
  };

  config = {
    # Configure NixOS-specific user properties from myConfig.users
    users.users = listToAttrs (map (user: {
        inherit (user) name;
        value = {
          isNormalUser = true;
          description = user.fullName;
          extraGroups = ["networkmanager" "wheel" "onepassword-secrets"];
          shell = pkgs.zsh;
        };
      })
      config.myConfig.users);

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
  };
}
