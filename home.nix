{ config, pkgs, ... }:

{
  home.username = "willweaver";
  home.stateVersion = "25.05";

  programs.home-manager.enable = true;

  programs.git = {
    enable = true;
    userName = "willweaver";
    userEmail = "me@willweaver.dev";
  };
}
