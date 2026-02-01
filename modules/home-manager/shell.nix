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

        # Start opencode web server and capture output
        output=$(ssh "$host" "opencode web --hostname 0.0.0.0" 2>&1)
        local exit_code=$?

        if [ $exit_code -ne 0 ]; then
          echo "❌ Error: Failed to start opencode web server on $host"
          echo "SSH output:"
          echo "$output"
          echo ""
          echo "Possible issues:"
          echo "  - opencode is not installed on $host"
          echo "  - Port is already in use on $host"
          echo "  - Permission issues on $host"
          return 1
        fi

        # Extract URLs from output
        network_url=$(echo "$output" | grep "Network access:" | sed 's/.*Network access:[[:space:]]*//' | tr -d '[:space:]')
        local_url=$(echo "$output" | grep "Local access:" | sed 's/.*Local access:[[:space:]]*//' | tr -d '[:space:]')

        if [ -z "$network_url" ] && [ -z "$local_url" ]; then
          echo "⚠️  Warning: Could not extract URLs from opencode output"
          echo "Raw output:"
          echo "$output"
          echo ""
          echo "The web server may still be running. Try accessing common ports on $host:"
          echo "  http://$host:4096"
          echo "  http://$host:3000"
          return 1
        fi

        echo "✅ OpenCode web server started successfully!"
        echo ""
        echo "📱 Access URLs:"
        [ -n "$local_url" ] && echo "   Local access:   $local_url"
        [ -n "$network_url" ] && echo "   Network access: $network_url"
        echo ""

        # Offer to open browser if we have a network URL
        if [ -n "$network_url" ]; then
          echo "🌐 Would you like to open the network URL in your browser? (y/N)"
          read -r response
          case "$response" in
            [yY][eE][sS]|[yY])
              if command -v open >/dev/null 2>&1; then
                echo "🚀 Opening $network_url in browser..."
                open "$network_url"
              elif command -v xdg-open >/dev/null 2>&1; then
                echo "🚀 Opening $network_url in browser..."
                xdg-open "$network_url"
              else
                echo "⚠️  Cannot automatically open browser - please manually visit: $network_url"
              fi
              ;;
            *)
              echo "👍 You can manually access the server at: $network_url"
              ;;
          esac
        fi

        echo ""
        echo "💡 To attach a terminal TUI to this server later:"
        echo "   ssh $host 'opencode attach $network_url'"
        echo ""
        echo "🛑 To stop the server, press Ctrl+C in the SSH session or run:"
        echo "   ssh $host 'pkill -f \"opencode web\"'"
      }
    '';
  };

  programs.home-manager.enable = true;
}
