{
  _config,
  pkgs,
  _lib,
  ...
}:
# NixOS module for the `devcontainer` machine.
# - Sets up the `opencode` user with zsh as the login shell
# - Configures devenv for project dependencies
# - Includes git and opencode configurations
{
  imports = [
    ./hardware-configuration.nix
  ];

  # Ensure the user exists with the desired shell and groups
  users.users.opencode = {
    isNormalUser = true;
    description = "opencode";
    extraGroups = ["networkmanager" "wheel" "docker"];
    # Use the zsh from nixpkgs as the login shell
    shell = pkgs.zsh;
    # Keep explicit home to match other entries; adjust if you prefer default
    home = "/home/opencode";
  };

  # Make sure zsh and devenv are available system-wide
  environment.systemPackages = with pkgs; [
    zsh
    devenv
    git
    # Add common development tools
    curl
    wget
    vim
    # Add task runner for opencode workflows
    go-task
  ];

  # Host/network/time/SSH settings for devcontainer
  networking = {
    hostName = "devcontainer";
    networkmanager.enable = true;
    firewall.allowedTCPPorts = [9000];
  };
  time.timeZone = "America/New_York";

  services.openssh.enable = true;

  # Enable Docker for container operations
  virtualisation.docker.enable = true;

  # Configure git for opencode user
  programs.git = {
    enable = true;
    config = {
      init.defaultBranch = "main";
      pull.rebase = true;
      push.autoSetupRemote = true;
    };
  };

  # Add devenv shell integration
  environment.shellInit = ''
    # Source devenv shell integration if available
    if [ -f ''${HOME}/.devenv/profile/etc/profile.d/devenv.sh ]; then
      source ''${HOME}/.devenv/profile/etc/profile.d/devenv.sh
    fi
  '';
}