# Core target - Minimal bootstrap configuration
# Uses modules/common/core.nix for absolute minimum packages
# This is a barebones configuration for fresh systems or recovery
# No additional configuration needed - core module provides:
# git, curl, vim, coreutils, zsh
_: {
  nixpkgs.hostPlatform = "aarch64-darwin";
  system.stateVersion = 4;
  nix.enable = false;
  myConfig = {
    users = [];
    agent-skills.enable = false;
    onepassword.enable = false;
    opencode.enable = false;
  };
}
