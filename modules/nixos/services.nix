{
  config,
  lib,
  pkgs,
  ...
}: {
  services = {
    # Jellyfin media server
    jellyfin = {
      enable = true;
      package = pkgs.unstable.jellyfin;
      openFirewall = true;
    };

    # Linkwarden bookmark manager
    # Note: This would need to be configured based on the actual service setup
    # linkwarden = {
    #   enable = true;
    #   # ... configuration
    # };

    # Mealie recipe manager
    mealie = {
      enable = true;
      database.createLocally = true;
      port = 9000;
    };

    # Syncthing file synchronization service
    syncthing = lib.mkIf config.myConfig.syncthing.enable {
      enable = true;
      user = (lib.head config.myConfig.users).name;
      dataDir = "/home/${(lib.head config.myConfig.users).name}/.config/syncthing";
      configDir = "/home/${(lib.head config.myConfig.users).name}/.config/syncthing";

      # GUI Configuration
      guiAddress = config.myConfig.syncthing.gui.address + ":" + toString config.myConfig.syncthing.gui.port;

      # Override default folders with user config
      overrideFolders = false;
      overrideDevices = false;

      # Open firewall for sync traffic
      openDefaultPorts = true;

      # Extra Options
      inherit extraOptions;
    };
  };

  # Firewall configuration for Syncthing
  networking.firewall = lib.mkIf config.myConfig.syncthing.enable {
    allowedTCPPorts = [
      config.myConfig.syncthing.gui.port # GUI
      22000 # Sync protocol
    ];
    allowedUDPPorts = [
      21027 # Discovery
    ];
  };
}
