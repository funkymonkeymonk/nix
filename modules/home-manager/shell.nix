{
  _config,
  lib,
  pkgs,
  ...
}: {
  # Import shell aliases module
  imports = [
    ./aliases.nix
  ];

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

      # Zinit - zsh plugin manager
      source ${pkgs.zinit}/share/zinit/zinit.zsh

      # Load z plugin for directory jumping (frecent directories)
      zinit load agkozak/zsh-z

      # FZF key bindings and completion
      source ${pkgs.fzf}/share/fzf/key-bindings.zsh
      source ${pkgs.fzf}/share/fzf/completion.zsh

      # Interactive directory jumping with z + fzf
      zz() {
        local dir
        dir=$(z -l 2>&1 | awk '{print $2}' | fzf --height 40% --reverse --prompt="Jump to: ") && cd "$dir"
      }

      # Find and cd to directory with fzf
      fd() {
        local dir
        dir=$(find ''${1:-.} -path '*/\.*' -prune -o -type d -print 2> /dev/null | fzf +m --prompt="Select directory: ") && cd "$dir"
      }

       # Drop-down terminal toggle function (macOS specific)
       ${lib.optionalString pkgs.stdenv.hostPlatform.isDarwin ''
        dropdown_terminal() {
          if pgrep -f "alacritty.*dropdown" > /dev/null; then
            pkill -f "alacritty.*dropdown"
          else
            nohup alacritty --class dropdown --title "dropdown-terminal" >/dev/null 2>&1 &
          fi
        }
      ''}

      # ISO to USB function
      ${lib.optionalString pkgs.stdenv.hostPlatform.isDarwin ''
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
              sudo dd if=./temp.img of=/dev/rdisk$disk_num bs=4M
            else
              echo Disk $disk_num is not found.
            fi
            rm temp.img
          else
            echo "Usage: iso2usb iso_file.iso"
          fi
        }
      ''}

      ${lib.optionalString pkgs.stdenv.hostPlatform.isLinux ''
        iso2usb() {
          if [ -f "$1" ]; then
            iso_name=$1
            lsblk
            echo "** Be careful. **"
            echo "This will wipe all data on the disk."
            echo "Which device would you like to install to (e.g., sdb):"
            read device

            if [ -b "/dev/$device" ]; then
              echo "Writing $iso_name to /dev/$device..."
              sudo dd if=$iso_name of=/dev/$device bs=4M status=progress
            else
              echo "Device /dev/$device is not found."
            fi
          else
            echo "Usage: iso2usb iso_file.iso"
          fi
        }
      ''}
    '';
  };

  programs.home-manager.enable = true;
}
