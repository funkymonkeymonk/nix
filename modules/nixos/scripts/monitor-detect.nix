{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.services.monitor-detect;
in {
  options.services.monitor-detect = {
    enable = mkEnableOption "Enable monitor detection service";
    user = mkOption {
      type = types.str;
      default = "monkey";
      description = "User to run monitor detection as";
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      (writeShellScriptBin "monitor-detect" ''
        #!/usr/bin/env bash
        # Detect connected displays
        xrandr --query | grep " connected" | wc -l
      '')
      xorg.xrandr
    ];
  };
}
