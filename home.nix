{ config, pkgs, ... }:

{
  home.username = "willweaver";
  home.stateVersion = "25.05";

  home.packages = with pkgs; [
    docker
  ];

  home.shellAliases = {
    g = "git";
    "..." = "cd ../..";
  };

  programs.home-manager.enable = true;

  programs.git = {
    enable = true;
    userName = "willweaver";
    userEmail = "me@willweaver.dev";
    aliases = {
      co = "checkout";
      st = "status";
    };
  };
}
