# Desktop environment configuration for NixOS
# Plasma 6, SDDM, PipeWire audio, Bluetooth
{
  config,
  lib,
  ...
}:
with lib; let
  cfg = config.myConfig.desktop;
in {
  options.myConfig.desktop = {
    enable = mkEnableOption "desktop environment";

    autoLoginUser = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "User to auto-login (null to disable)";
    };
  };

  config = mkIf cfg.enable {
    services = {
      displayManager = {
        sddm = {
          enable = true;
          wayland.enable = true;
        };
        autoLogin = mkIf (cfg.autoLoginUser != null) {
          enable = true;
          user = cfg.autoLoginUser;
        };
      };

      desktopManager.plasma6.enable = true;

      printing.enable = true;

      # PipeWire audio (replaces PulseAudio)
      pulseaudio.enable = false;
      pipewire = {
        enable = true;
        alsa.enable = true;
        alsa.support32Bit = true;
        pulse.enable = true;
      };

      # Bluetooth manager
      blueman.enable = true;
    };

    # Bluetooth hardware
    hardware.bluetooth = {
      enable = true;
      powerOnBoot = true;
      settings.General.Experimental = true;
    };

    # KDE Connect for phone integration
    programs.kdeconnect.enable = true;

    # Required for PipeWire
    security.rtkit.enable = true;
  };
}
