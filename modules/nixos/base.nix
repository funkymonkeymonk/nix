# Shared NixOS configuration for all targets
# Configures users from myConfig with NixOS-specific settings and auto-upgrade
{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
with lib; {
  imports = [
    ./ghostty-terminfo.nix
  ];

  config = mkIf (!config.myConfig.isDarwin) {
    # Configure NixOS-specific user properties from myConfig.users
    users.users = listToAttrs (map (user: {
        inherit (user) name;
        value = {
          isNormalUser = true;
          description = user.fullName;
          extraGroups = ["networkmanager" "wheel"];
          shell = pkgs.zsh;
        };
      })
      config.myConfig.users);

    # Ensure zsh is available system-wide
    environment.systemPackages = [pkgs.zsh];

    # Enable SSH
    services.openssh.enable = true;

    # Auto-upgrade configuration
    system.autoUpgrade = {
      enable = true;
      flake = inputs.self.outPath;
      flags = ["-L"];
      dates = "02:00";
      randomizedDelaySec = "45min";
    };
  };
}
