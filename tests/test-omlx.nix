# oMLX Darwin configuration tests.
{pkgs, ...}: let
  inherit (pkgs) lib;

  modules = [
    {
      options.myConfig.users = lib.mkOption {
        type = lib.types.listOf lib.types.anything;
        default = [];
      };
      options.myConfig.serviceRegistry = lib.mkOption {
        type = lib.types.attrs;
        default = {};
      };
      options.homebrew = lib.mkOption {
        type = lib.types.attrs;
        default = {};
      };
      options.launchd.user.agents = lib.mkOption {
        type = lib.types.attrs;
        default = {};
      };
      options.system.activationScripts = lib.mkOption {
        type = lib.types.attrs;
        default = {};
      };
      config._module.args = {inherit pkgs;};
    }
    ../modules/services/omlx/darwin.nix
    {
      config.myConfig.omlx.enable = true;
    }
  ];

  evaluated = (lib.evalModules {inherit modules;}).config;
  omlxBrew = builtins.head evaluated.homebrew.brews;
  mountAgent = evaluated.launchd.user.agents.metal-toolchain-mount;
in {
  omlxCustomKernelHomebrewTest = pkgs.runCommand "test-omlx-custom-kernel-homebrew" {} ''
    ${
      if omlxBrew.args == ["with-custom-kernel"]
      then ''echo "oMLX custom-kernel Homebrew args are enabled: OK"''
      else ''echo "oMLX custom-kernel Homebrew args are missing"; exit 1''
    }
    touch $out
  '';

  metalToolchainMountAgentTest = pkgs.runCommand "test-omlx-metal-toolchain-mount-agent" {} ''
    ${
      if mountAgent.serviceConfig.RunAtLoad
      then ''echo "Metal toolchain mount runs at login: OK"''
      else ''echo "Metal toolchain mount must run at login"; exit 1''
    }
    ${
      if mountAgent.serviceConfig.StartInterval == 300
      then ''echo "Metal toolchain mount retries every 300 seconds: OK"''
      else ''echo "Metal toolchain mount must retry every 300 seconds"; exit 1''
    }
    ${
      if builtins.elem "/Volumes" mountAgent.serviceConfig.WatchPaths
      then ''echo "Metal toolchain mount watches /Volumes: OK"''
      else ''echo "Metal toolchain mount must watch /Volumes"; exit 1''
    }
    ${
      if lib.hasInfix "com_apple_MobileAsset_MetalToolchain" mountAgent.script
      then ''echo "Metal toolchain asset path is configured: OK"''
      else ''echo "Metal toolchain asset path is missing"; exit 1''
    }
    ${
      if lib.hasInfix "/Volumes/MetalToolchainCryptex" mountAgent.script
      then ''echo "Metal toolchain Cryptex mountpoint is configured: OK"''
      else ''echo "Metal toolchain Cryptex mountpoint is missing"; exit 1''
    }
    touch $out
  '';
}
