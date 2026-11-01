# Base Darwin archetype
#
# Shared boilerplate for every darwinConfigurations entry:
# - Main modules directory (roles, common modules)
# - Darwin OS defaults (dark mode, allowUnfree, no home-manager docs)
# - Home-manager integration with opnix shared modules
#
# This does NOT include the nixpkgs configuration/overlays from flake.nix's
# `configuration` let-binding — that stays in flake.nix because it references
# `self` (the flake itself) which is not available via module specialArgs.
{
  config,
  inputs,
  lib,
  ...
}: let
  sshPublicKey = import ../ssh-public-key.nix;
in {
  imports = [
    ../../modules
    ../../os/darwin.nix
    inputs.home-manager.darwinModules.home-manager
  ];

  home-manager.sharedModules = [inputs.opnix.homeManagerModules.default];

  users.users = lib.listToAttrs (map (user: {
      name = user.name;
      value.openssh.authorizedKeys.keys = [sshPublicKey];
    })
    config.myConfig.users);

  services.openssh.enable = lib.mkDefault config.myConfig.ssh.enable;
}
