{
  config,
  pkgs,
  ...
}: {
  home.username = "willweaver";
  home.stateVersion = "25.05";

  home.packages = with pkgs; [
    docker
  ];

  programs.home-manager.enable = true;

  programs.zsh = {
    enable = true;
    initContent = ''
      # Docker
      drm() { docker rm $(docker ps -q -a); }
      dri() { docker rmi $(docker images -q); }
      db() { docker build -t="$1" .; }
      dps() { docker ps -a; }

      # Direnv
      eval "$(direnv hook zsh)"

      iso2usb() {
        if [ -f "$1" ]; then
          iso_name=$1
          hdiutil convert -format UDRW -o ./temp.img $iso_name
          mv temp.img.dmg temp.img
          diskutil list
          echo "** Be careful. **"
          echo "This will wipe all data on the disk."
          echo "Which disk number would you like to install to:"
          read disk_num

          if [ -b "/dev/disk$disk_num" ]; then
            diskutil unmountDisk /dev/disk$disk_num
            sudo dd if=./temp.img of=/dev/rdisk$disk_num bs=1m
          else
            echo Disk $disk_num is not found.
          fi
          rm temp.img
        else
          echo "Usage: iso2usb iso_file.iso"
        fi
      }
    '';
  };

  home.shellAliases = {
    g = "git";
    t = "task";
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

  services.syncthing = {
    enable = true;
  };
}
