{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.myConfig.onepassword;
  isDarwin = builtins.elem config.nixpkgs.hostPlatform.system ["aarch64-darwin" "x86_64-darwin"];
  isLinux = builtins.elem config.nixpkgs.hostPlatform.system ["x86_64-linux" "aarch64-linux"];
in {
  # This module only defines options for 1Password
  # The actual configuration is handled in the home-manager modules
  # and bundles to avoid module system conflicts
}
