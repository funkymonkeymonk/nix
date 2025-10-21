{ config, lib, pkgs, ... }:
{
  programs.zsh = {
    enable = true;
    initContent = ''
      # Docker functions
      drm() { docker rm $(docker ps -q -a); }
      dri() { docker rmi $(docker images -q); }
      db() { docker build -t="$1" .; }
      dps() { docker ps -a; }

      # Direnv
      eval "$(direnv hook zsh)"

      # ISO to USB function (macOS specific)
      ${lib.optionalString pkgs.stdenv.isDarwin ''
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
      ''}
    '';
  };

  home.shellAliases = {
    g = "git";
    t = "task";
    tb = "task build";
    tt = "task test";
    "..." = "cd ../..";
    dip = "docker inspect --format '{{ .NetworkSettings.IPAddress }}'";
    dkd = "docker run -d -P";
    dki = "docker run -t -i -P";
    gauc = "git add -u && git commit -m ";
    gst = "git status";
    gaum = "git add -u && git commit --amend";
    gpush = "git push";
    gpull = "git pull";
    gd = "git diff";
    gdc = "git diff --cached";
    gco = "git checkout";
    ghv = "gh repo view --web";
    gs = "git stash";
    gsp = "git stash pop";
    gshow = "git stash show -p";
    grm = "git fetch origin && git rebase main";
    grc = "git rebase --continue";
    gm = "git merge";
    gmm = "git fetch origin && git git merge origin/main";
    gf = "git fetch --prune";
    gr = "git restore --source";
    grh = "git reset --hard";
    try = "nix-shell -p";
  };

  programs.home-manager.enable = true;
}