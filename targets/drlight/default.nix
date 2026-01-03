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
    # TODO: Re-enable when secret management is implemented
    # ../../modules/nixos/linkwarden.nix
  ];

  # Ensure the user exists with the desired shell and groups
  users.users.monkey = {
    isNormalUser = true;
    description = "monkey";
    extraGroups = ["networkmanager" "wheel"];
    # Use the zsh from nixpkgs as the login shell
    shell = pkgs.zsh;
    # Keep explicit home to match other entries; adjust if you prefer default
    home = "/home/monkey";
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

    # TODO: Enable OpNix for secret management (service module not yet implemented)
    # onepassword-secrets = {
    #   enable = true;
    #   tokenFile = "/etc/opnix-token";
    #   secrets = {
    #     linkwardenDbPassword = {
    #       reference = "op://Homelab/Linkwarden Database Password/password";
    #       owner = "linkwarden";
    #       services = ["linkwarden"];
    #     };
    #     nextauthSecret = {
    #       reference = "op://Homelab/Linkwarden NextAuth Secret/password";
    #       owner = "linkwarden";
    #       services = ["linkwarden"];
    #     };
    #     meilisearchKey = {
    #       reference = "op://Homelab/Meilisearch Key/password";
    #       owner = "meilisearch";
    #       services = ["meilisearch"];
    #     };
    #     meilisearchDbPassword = {
    #       reference = "op://Homelab/Meilisearch Database/password";
    #       owner = "meilisearch";
    #       services = ["meilisearch"];
    #     };
    #   };
    # };

    # Enable services
    postgresql.enable = true;
    # TODO: Re-enable when secret management is implemented
    # meilisearch.enable = true;
    # linkwarden = {
    #   enable = true;
    #   port = 3000;
    #   openFirewall = true;
    # };
  };
}
