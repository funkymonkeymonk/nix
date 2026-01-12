{
  _config,
  pkgs,
  _lib,
  ...
}:
# NixOS module for the `drlight` machine.
# - Sets up the `monkey` user with zsh as the login shell
# - Installs zsh system-wide
# - Configures basic networking / SSH settings used in flake.nix
# - Enables PostgreSQL, Meilisearch, and Linkwarden services
{
  imports = [
    ./hardware-configuration.nix
  ];

  # Ensure users exist with desired configuration and groups
  users.users = {
    monkey = {
      isNormalUser = true;
      description = "monkey";
      extraGroups = ["networkmanager" "wheel"];
      # Use the zsh from nixpkgs as the login shell
      shell = pkgs.zsh;
      # Keep explicit home to match other entries; adjust if you prefer default
      home = "/home/monkey";
    };

    # Add service users to onepassword-secrets group to access secrets
    postgres.extraGroups = ["onepassword-secrets"];
    linkwarden.extraGroups = ["onepassword-secrets"];
  };

  # Make sure zsh is available system-wide (so the shell path exists)
  environment.systemPackages = with pkgs; [
    zsh
  ];

  # Host/network/time/SSH settings for drlight
  networking = {
    hostName = "drlight";
    networkmanager.enable = true;
    firewall.allowedTCPPorts = [9000 3000]; # Mealie + Linkwarden
  };
  time.timeZone = "America/New_York";

  # Services configuration
  services = {
    openssh.enable = true;

    # Enable OpNix for secret management using brizzbuzz/opnix module
    onepassword-secrets = {
      enable = true;
      tokenFile = "/etc/opnix-token";
      outputDir = "/run/opnix/secrets";
      secrets = {
        linkwardenDbPassword = {
          reference = "op://Homelab/Linkwarden Database Password/password";
          owner = "linkwarden";
          group = "onepassword-secrets";
          mode = "0640"; # Group-readable for security
          services = ["linkwarden"];
        };
        meilisearchDbPassword = {
          reference = "op://Homelab/Meilisearch Database/password";
          owner = "postgres";
          services = []; # Used by set-postgres-passwords service
        };
        nextauthSecret = {
          reference = "op://Homelab/Linkwarden NextAuth Secret/password";
          owner = "linkwarden";
          group = "onepassword-secrets";
          mode = "0640"; # Group-readable for security
          services = ["linkwarden"];
        };
      };
    };

    postgresql.enable = true;

    # Enable linkwarden service
    linkwarden = {
      enable = true;
      port = 3000;
      openFirewall = true;
    };
  };
}
