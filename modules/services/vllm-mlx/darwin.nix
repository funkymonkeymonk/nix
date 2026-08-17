# vllm-mlx inference server launched service for Darwin (macOS)
# Uses the Nix-packaged vllm-mlx binary (no runtime uv install).
# Supports pre-downloaded models via pkgs.mlx-models overlays.
{
  config,
  lib,
  pkgs,
  ...
}: let
  commonLib = import ../../common/lib.nix {inherit lib;};
  vllmLib = import ./lib.nix {inherit lib pkgs;};

  primaryUser = commonLib.primaryUser config;
  darwinHomeDir = commonLib.darwinHomeDir config;
  cfg = config.myConfig.vllmMlx;
in {
  options.myConfig.vllmMlx = lib.mkOption {
    type = lib.types.submodule (import ./instance-options.nix);
    default = {};
    description = "Default vllm-mlx inference server instance.";
  };

  config = lib.mkIf cfg.enable (vllmLib.mkInstance {
    name = "default";
    instanceCfg = cfg;
    inherit primaryUser darwinHomeDir;
  });
}
