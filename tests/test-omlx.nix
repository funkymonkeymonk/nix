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
      options.launchd.daemons = lib.mkOption {
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
      config.myConfig.users = [{name = "monkey";}];
      config.myConfig.omlx.enable = true;
    }
  ];

  evaluated = (lib.evalModules {inherit modules;}).config;
  omlxBrew = builtins.head evaluated.homebrew.brews;
  omlxTap = builtins.head evaluated.homebrew.taps;
  omlxDaemon = evaluated.launchd.daemons.omlx or {};
  mountDaemon = evaluated.launchd.daemons.metal-toolchain-mount or {};
  omlxDaemonService = omlxDaemon.serviceConfig or {};
in {
  omlxCustomKernelHomebrewTest = pkgs.runCommand "test-omlx-custom-kernel-homebrew" {} ''
    ${
      if omlxBrew.args == ["with-custom-kernel"]
      then ''echo "oMLX custom-kernel Homebrew args are enabled: OK"''
      else ''echo "oMLX custom-kernel Homebrew args are missing"; exit 1''
    }
    touch $out
  '';

  omlxBootDaemonTest = pkgs.runCommand "test-omlx-boot-daemon" {} ''
    echo "=== Testing oMLX boot daemon configuration ==="
    ${
      if (omlxDaemonService.UserName or "") == "monkey"
      then ''echo "oMLX runs as the primary user at boot: OK"''
      else ''echo "FAIL: oMLX boot daemon must run as monkey"; exit 1''
    }
    ${
      if (omlxDaemonService.RunAtLoad or false) && (omlxDaemonService.KeepAlive or false)
      then ''echo "oMLX starts at boot and restarts after exit: OK"''
      else ''echo "FAIL: oMLX daemon needs RunAtLoad and KeepAlive"; exit 1''
    }
    ${
      if !(evaluated.launchd.user.agents ? omlx)
      then ''echo "oMLX does not depend on a user login agent: OK"''
      else ''echo "FAIL: oMLX must not be a user LaunchAgent"; exit 1''
    }
    SCRIPT=${omlxDaemon.command or ""}
    if grep -q -- '--host 127.0.0.1' "$SCRIPT"; then
      echo "oMLX API binds to loopback behind Bifrost: OK"
    else
      echo "FAIL: oMLX API must bind to loopback"; exit 1
    fi
    if grep -q '127.0.0.1:8300/health' "$SCRIPT" && grep -q 'startup readiness timed out' "$SCRIPT" && grep -q 'exited before startup readiness' "$SCRIPT"; then
      echo "oMLX startup is health-checked and fails promptly on timeout or exit: OK"
    else
      echo "FAIL: oMLX launcher must detect readiness timeout and early process exit"; exit 1
    fi
    ${pkgs.bash}/bin/bash -n "$SCRIPT"
    touch $out
  '';

  metalToolchainMountDaemonTest = pkgs.runCommand "test-omlx-metal-toolchain-mount-daemon" {} ''
    ${
      if (mountDaemon.serviceConfig.RunAtLoad or false) && (mountDaemon.serviceConfig.StartInterval or 0) == 300
      then ''echo "Metal toolchain mount starts at boot and retries: OK"''
      else ''echo "FAIL: Metal toolchain mount daemon must run at boot and retry"; exit 1''
    }
    ${
      if builtins.elem "/Volumes" (mountDaemon.serviceConfig.WatchPaths or [])
      then ''echo "Metal toolchain mount watches /Volumes: OK"''
      else ''echo "FAIL: Metal toolchain mount must watch /Volumes"; exit 1''
    }
    ${
      if lib.hasInfix "com_apple_MobileAsset_MetalToolchain" (mountDaemon.script or "")
      then ''echo "Metal toolchain asset path is configured: OK"''
      else ''echo "FAIL: Metal toolchain asset path is missing"; exit 1''
    }
    ${
      if lib.hasInfix "/Volumes/MetalToolchainCryptex" (mountDaemon.script or "")
      then ''echo "Metal toolchain Cryptex mountpoint is configured: OK"''
      else ''echo "FAIL: Metal toolchain mountpoint is missing"; exit 1''
    }
    touch $out
  '';

  omlxHomebrewUpdatePolicyTest = pkgs.runCommand "test-omlx-homebrew-update-policy" {} ''
    ${
      if !(evaluated.homebrew.onActivation.autoUpdate or true) && !(evaluated.homebrew.onActivation.upgrade or true) && !(evaluated.homebrew.global.autoUpdate or true) && !(omlxTap.force_auto_update or true)
      then ''echo "Homebrew runtime and tap upgrades are deliberate: OK"''
      else ''echo "FAIL: Homebrew oMLX and its tap must not auto-update"; exit 1''
    }
    touch $out
  '';
}
