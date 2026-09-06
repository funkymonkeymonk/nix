# Headless Darwin server archetype
#
# Generic headless macOS server profile:
# - SSH hardened (keys only, no root)
# - Lume VM runtime for macOS VMs
# - Developer & opencode tools for remote management
# - No heavy LLM stack (remote APIs only)
{
  inputs,
  pkgs,
  ...
}: {
  imports = [
    ./base-darwin.nix
    ../../modules/services/lume/darwin.nix
    ../../modules/services/prometheus/darwin.nix
    ../../modules/services/node-exporter/darwin.nix
    ../../modules/services/alertmanager/darwin.nix
    ../../modules/services/loki/darwin.nix
    ../../modules/services/vector/darwin.nix
    ../../modules/services/grafana/darwin.nix
  ];

  myConfig = {
    skills.superpowersPath = inputs.superpowers or null;

    roles = {
      developer.enable = true; # Basic dev tools for VM management
      opencode.enable = true; # AI assistant for management tasks
    };

    opencode = {
      enable = true;
      model = "local-bifrost/omlx/qwen3.8-27b";
    };

    llmClient.rtk.enable = true;

    lume = {
      enable = true;
      enableBackgroundService = true;
      port = 7777;
      enableAutoUpdater = true;
      prePullImages = ["macos-tahoe-vanilla:latest"];
    };

    # Native observability stack for headless Darwin servers.
    prometheus.enable = true;
    nodeExporter.enable = true;
    alertmanager.enable = true;
    loki.enable = true;
    vector.enable = true;
    grafana.enable = true;
  };

  # SSH hardening (Darwin uses extraConfig, not settings.)
  services.openssh = {
    enable = true;
    extraConfig = ''
      PermitRootLogin no
      PubkeyAuthentication yes
      PasswordAuthentication no
      AllowAgentForwarding yes
    '';
  };

  users.users.root.openssh.authorizedKeys.keys = [];

  # Passwordless sudo for remote deployment (deploy-rs)
  security.sudo.extraConfig = ''
    Defaults timestamp_timeout=0
    monkey ALL=(ALL) NOPASSWD: ALL
  '';

  # Basic management tools
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
