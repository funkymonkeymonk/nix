# Cachix binary cache configuration
# Configures nix to pull from the funkymonkeymonk Cachix cache
#
# For Darwin with Determinate Nix (nix.enable = false), this uses nix.settings
# which still works for extra-* options even when nix-darwin doesn't manage nix.conf
#
# For NixOS, this merges with existing nix.settings
{
  config,
  lib,
  ...
}: let
  cfg = config.myConfig;
in {
  options.myConfig.cachix = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable Cachix binary cache";
    };
  };

  config = lib.mkIf cfg.cachix.enable {
    nix.settings = {
      substituters = [
        "https://funkymonkeymonk.cachix.org"
      ];
      trusted-public-keys = [
        "funkymonkeymonk.cachix.org-1:SO7Wri4Z3GFCMY8IaX6u3okXKVX8qjMtxag2hwgG6uI="
      ];
    };
  };
}
