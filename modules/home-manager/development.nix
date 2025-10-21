{ config, lib, pkgs, ... }:
{
  home.packages = with pkgs; [
    docker
  ];

  programs.alacritty = {
    enable = true;
    settings = {
      font.size = 14;
      window.decorations = "Buttonless";
      window.padding = {
        x = 10;
        y = 6;
      };
      mouse.hide_when_typing = true;
    };
  };

  programs.kitty = {
    enable = true;
    shellIntegration.enableZshIntegration = true;
  };

  programs.emacs = {
    enable = true;
    package = if pkgs.stdenv.isDarwin then pkgs.emacs-macport else pkgs.emacs;
    extraConfig = ''
      (setq standard-indent 2)
    '';
  };

  services.syncthing.enable = true;
}