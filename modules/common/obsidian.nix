# myConfig.obsidian options — owned here, consumed by modules/home-manager/obsidian.nix
# (loaded conditionally via modules/common/users.nix) and set by
# modules/roles/desktop.nix.
{lib, ...}: {
  options.myConfig.obsidian = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable Obsidian note-taking app via home-manager";
    };

    vaultRoot = lib.mkOption {
      type = lib.types.str;
      default = "~/Documents/vaults";
      description = ''
        Root directory for all Obsidian vaults. Each vault name in
        `myConfig.obsidian.vaults` becomes a subdirectory here.
      '';
    };

    vaults = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      example = ["personal" "work"];
      description = ''
        Names of Obsidian vaults on this machine. Each name creates a vault at
        `<vaultRoot>/<name>` and a corresponding Syncthing folder.
      '';
    };

    syncAllVaults = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Sync all known vault names via Syncthing regardless of whether Obsidian
        is enabled. Intended for backup servers or machines that should mirror
        every vault without running Obsidian itself.

        When false (default), only vaults listed in `myConfig.obsidian.vaults`
        are synced. When true, the machine participates in syncing all vault
        folder IDs it knows about.
      '';
    };

    allVaults = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      example = ["personal" "work"];
      description = ''
        Exhaustive list of all vault names that exist across every machine.
        Only used when `syncAllVaults = true` to register Syncthing folders
        for vaults not listed in `myConfig.obsidian.vaults`.
      '';
    };
  };
}
