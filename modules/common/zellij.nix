# myConfig.zellij option — owned here, consumed by modules/home-manager/zellij.nix
# (loaded conditionally via modules/common/users.nix) and set by
# modules/roles/developer.nix.
{lib, ...}: {
  options.myConfig.zellij = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable zellij terminal multiplexer configuration";
    };
  };
}
