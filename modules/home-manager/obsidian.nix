{
  osConfig,
  lib,
  pkgs,
  ...
}: let
  cfg = osConfig.myConfig.obsidian;

  # Build a programs.obsidian.vaults attrset from the vault name list.
  # Each vault gets target = "<vaultRoot>/<name>" (tilde is expanded by HM).
  vaultAttrs = lib.listToAttrs (
    map (name: {
      inherit name;
      value = {
        target = "${cfg.vaultRoot}/${name}";
      };
    })
    cfg.vaults
  );
in {
  config = lib.mkIf cfg.enable {
    programs.obsidian = {
      enable = true;
      package = pkgs.obsidian;
      vaults = vaultAttrs;
    };
  };
}
