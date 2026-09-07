# Gaming configuration for NixOS
# Steam, gamemode, controller support (Xbox One/xpadneo)
{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.myConfig.gaming;
in {
  options.myConfig.gaming = {
    enable = mkEnableOption "gaming support";
  };

  config = mkIf cfg.enable {
    programs = {
      steam = {
        enable = true;
        remotePlay.openFirewall = true;
        gamescopeSession.enable = true;
        # xpadneo exposes Xbox Bluetooth controllers with correct SDL
        # mappings via evdev/joydev, but Steam/SDL2 reads them over hidraw
        # through the SDL_JOYSTICK_HIDAPI driver, which produces wrong or
        # absent mappings — Steam detects the controller but games receive
        # no input. Disable the HIDAPI joystick driver so Steam uses the
        # xpadneo-provided evdev path instead. The env var must be set both
        # in the FHS package profile and in gamescopeSession.env: the
        # steam-gamescope session wrapper only exports gamescopeSession.env.
        package = pkgs.steam.override {
          extraEnv = {
            SDL_JOYSTICK_HIDAPI = "0";
          };
        };
        gamescopeSession.env = {
          SDL_JOYSTICK_HIDAPI = "0";
        };
      };
      gamemode.enable = true;
    };

    # Xbox controller support
    hardware = {
      xone.enable = true;
      xpadneo.enable = true;
    };

    # Gaming packages
    environment.systemPackages = with pkgs; [
      lutris
      protonup-qt
    ];
  };
}
