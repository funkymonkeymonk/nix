{
  config,
  pkgs,
  ...
}: {
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

  # I don't want to lose this function during the transitional period
  # but I want to migrate out of the shell.dotfile. So this is disk-usage.
  # I may want to replace this but I also may want to keep it around.
  #
  # disk-usage() {
  #   path=${1-${PWD}}
  #   du -k $path | sort -n | perl -ne 'if ( /^(\d+)\s+(.*$)/){$l=log($1+.1);$m=int($l/log(1024)); printf  ("%6.1f\t%s\t%25s  %s\n",($1/(2**(10*$m))),(("K","M","G","T","P")[$m]),"*"x (1.5*$l),$2);}'
  # }

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
  };

  programs.git = {
    enable = true;
    userName = "willweaver";
    userEmail = "me@willweaver.dev";
    aliases = {
      co = "checkout";
      st = "status";
    };
    difftastic = {
      enable = true;
      background = "dark";
    };
    extraConfig = {
      pull = {
        rebase = "true";
      };
      push = {
        default = "current";
      };
      # "core.editor" = "emacsclient -c -a 'emacs'";
    };
  };

  services.syncthing = {
    enable = true;
  };
}
