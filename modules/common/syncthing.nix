# myConfig.syncthing option — owned here, consumed by modules/home-manager/foundation.nix
# and set by modules/roles/foundation.nix.
{lib, ...}: {
  options.myConfig.syncthing = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable Syncthing file synchronization";
    };
  };
}
