# Generates launchd services for additional vllm-mlx instances defined in
# myConfig.vllmMlxInstances. The option itself is defined in
# darwin-instances-options.nix to avoid infinite recursion.
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

  enabledInstances = lib.filterAttrs (_: instanceCfg: instanceCfg.enable) config.myConfig.vllmMlxInstances;

  instanceConfigs = lib.mapAttrs (name: instanceCfg:
    vllmLib.mkInstance {
      inherit name instanceCfg primaryUser darwinHomeDir;
    })
  enabledInstances;
in {
  config = lib.mkIf (enabledInstances != {}) {
    launchd.daemons = lib.foldl' (a: b: a // b) {} (lib.attrValues (lib.mapAttrs (_: c: c.launchd.daemons) instanceConfigs));

    system.activationScripts.postActivation.text = lib.mkAfter (
      lib.concatStringsSep "\n" (lib.attrValues (lib.mapAttrs (_: c:
        c.system.activationScripts.postActivation.text.content)
      instanceConfigs))
    );

    myConfig.serviceRegistry = lib.foldl' (a: b: a // b) {} (lib.attrValues (lib.mapAttrs (_: c: c.myConfig.serviceRegistry) instanceConfigs));
  };
}
