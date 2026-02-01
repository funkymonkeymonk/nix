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
          if pgrep -f "alacritty.*dropdown" > /dev/null; then
            pkill -f "alacritty.*dropdown"
          else
            nohup alacritty --class dropdown --title "dropdown-terminal" >/dev/null 2>&1 &
          fi
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

      # Function to start opencode web session on any SSH host with robust error handling
      ocssh() {
        local host="$1"
        local output
        local network_url
        local local_url

        # Check if host parameter is provided
        if [ -z "$host" ]; then
          echo "❌ Error: Host parameter required"
          echo "Usage: ocssh <hostname>"
          echo "Example: ocssh drlight"
          return 1
        fi

        echo "🔍 Checking SSH connectivity to $host..."
        if ! ssh -o ConnectTimeout=5 -o BatchMode=yes "$host" "echo 'Connection successful'" 2>/dev/null; then
          echo "❌ Error: Cannot connect to $host via SSH"
          echo "Please check:"
          echo "  - $host is reachable on the network"
          echo "  - Your SSH key is configured for $host"
          echo "  - SSH agent is running (if using key authentication)"
          return 1
        fi

        echo "✅ SSH connection verified"
        echo "🚀 Starting opencode web server on $host..."
        echo "   This may take a few seconds to initialize..."

        echo "🚀 Starting opencode web server on $host..."
        echo "   (Server will run in background - use Ctrl+C to return to shell)"
        echo ""

        # Start opencode web server directly - it will show URLs and continue running
        ssh "$host" "opencode web --hostname 0.0.0.0" &
        local ssh_pid=$!

        # Give the server a moment to start
        sleep 3

        # Check if the SSH process is still running (server should be)
        if ! kill -0 $ssh_pid 2>/dev/null; then
          echo ""
          echo "❌ Error: opencode web server failed to start or exited immediately"
          echo ""
          echo "Possible issues:"
          echo "  - opencode is not installed on $host"
          echo "  - Port is already in use on $host"
          echo "  - SSH authentication issues"
          echo ""
          echo "To debug, try running manually:"
          echo "   ssh $host 'opencode web --hostname 0.0.0.0'"
          return 1
        fi

        echo ""
        echo "✅ OpenCode web server is running on $host!"
        echo ""
        echo "📱 To access the web interface:"
        echo "   1. Check the server output above for network URLs"
        echo "   2. Common ports: http://$host:4096, http://$host:3000"
        echo "   3. Use 'opencode attach http://$host:<port>' to attach terminal"
        echo ""
        echo "💡 To stop the server later:"
        echo "   ssh $host 'pkill -f \"opencode web\"'"
        echo ""
        echo "🔗 Press Ctrl+C to return to shell (server continues running)"
      }
    '';
  };

  programs.home-manager.enable = true;
}
