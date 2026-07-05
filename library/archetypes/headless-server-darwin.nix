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
    ../../modules/services/lume/darwin.nix
  ];

  myConfig = {
    skills.superpowersPath = inputs.superpowers or null;

    roles = {
      developer.enable = true; # Basic dev tools for VM management
      opencode.enable = true; # AI assistant for management tasks
    };

    opencode = {
      enable = true;
      model = null; # User selects on first run
    };

    llmClient.rtk.enable = true;

    lume = {
      enable = true;
      enableBackgroundService = true;
      port = 7777;
      enableAutoUpdater = true;
      prePullImages = ["macos-tahoe-vanilla:latest"];
    };
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
  '';

  # Basic management tools
  environment.systemPackages = with pkgs; [
    curl
    jq
  ];

  time.timeZone = "America/New_York";
}
