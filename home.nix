{ config, pkgs, ... }:

{
  home.username = "willweaver";
  home.stateVersion = "25.05";

  home.packages = with pkgs; [
    docker
  ];

  programs.home-manager.enable = true;

  programs.zsh = {
    enable = true;
    initExtra = ''
      drm() { docker rm $(docker ps -q -a); }
      dri() { docker rmi $(docker images -q); }
      db() { docker build -t="$1" .; }
      dps() { docker ps -a; }
      eval "$(direnv hook zsh)"
    '';
  };

  home.shellAliases = {
    g = "git";
    "..." = "cd ../..";
    dip = "docker inspect --format '{{ .NetworkSettings.IPAddress }}'";
    dkd = "docker run -d -P";
    dki = "docker run -t -i -P";
  };

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
