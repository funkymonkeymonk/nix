# Headless Darwin host for managing macOS virtual machines.
{pkgs, ...}: {
  imports = [
    ./base-darwin.nix
    ./server-observability-darwin.nix
    ../../modules/nixos/ghostty-terminfo.nix
    ../../modules/services/lume/darwin.nix
  ];

  myConfig = {
    roles = {
      developer.enable = true;
      opencode.enable = true;
    };

    opencode.enable = true;
    llmClient.rtk.enable = true;

    lume = {
      enable = true;
      enableBackgroundService = true;
      port = 7777;
      enableAutoUpdater = true;
      prePullImages = ["macos-tahoe-vanilla:latest"];
    };
  };

  # Apply key-only SSH policy only when a host opts in through myConfig.ssh.enable.
  services.openssh.extraConfig = ''
    PermitRootLogin no
    PubkeyAuthentication yes
    PasswordAuthentication no
    AllowAgentForwarding yes
  '';

  users.users.root.openssh.authorizedKeys.keys = [];

  # Passwordless sudo for remote deployment (deploy-rs).
  security.sudo.extraConfig = ''
    Defaults timestamp_timeout=0
    monkey ALL=(ALL) NOPASSWD: ALL
  '';

  environment.systemPackages = with pkgs; [
    curl
    jq
  ];

  environment.etc."newsyslog.d/lume-services.conf".text = ''
    # Rotate Lume daemon logs while retaining recent history.
    /tmp/lume_daemon.log    root:wheel  644  5  10000 *  G
    /tmp/lume_daemon.err    root:wheel  644  5  10000 *  G
  '';

  time.timeZone = "America/New_York";
}
