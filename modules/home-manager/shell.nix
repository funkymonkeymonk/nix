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

      # Drop-down terminal toggle function (macOS specific)
      ${lib.optionalString pkgs.stdenv.isDarwin ''
        dropdown_terminal() {
          osascript -e "
          tell application \"Alacritty\"
            try
              set visible of window 1 to not (visible of window 1)
            on error
              do shell script \"open -n /Applications/Alacritty.app --args --class dropdown\"
            end try
          end tell
          "
        }
      ''}

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

  programs.home-manager.enable = true;
}
