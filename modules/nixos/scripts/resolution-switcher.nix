{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.services.resolution-switcher;
in {
  options.services.resolution-switcher = {
    enable = mkEnableOption "Enable dynamic resolution switching service";
    user = mkOption {
      type = types.str;
      default = "monkey";
      description = "User to run resolution switcher as";
    };
    virtualDisplay = mkOption {
      type = types.str;
      default = ":99";
      description = "Virtual display identifier";
    };
    supportedResolutions = mkOption {
      type = types.listOf types.str;
      default = ["3840x2160" "3440x1440" "2560x1440" "1920x1080"];
      description = "List of supported resolutions";
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      (writeShellScriptBin "resolution-detect" ''
        #!/usr/bin/env bash
        # Resolution detection script for virtual display

        VIRTUAL_DISPLAY="''${VIRTUAL_DISPLAY:-:99}"
        export DISPLAY=$VIRTUAL_DISPLAY

        # Get current resolution
        CURRENT_RES=$(xrandr --current 2>/dev/null | grep "*" | awk '{print $1}' | head -n1)

        if [ -z "$CURRENT_RES" ]; then
          echo "No resolution detected or display not available"
          exit 1
        fi

        echo "Current resolution: $CURRENT_RES"

        # List supported resolutions
        echo ""
        echo "Supported resolutions:"
        for res in ${concatStringsSep " " cfg.supportedResolutions}; do
          if [ "$res" = "$CURRENT_RES" ]; then
            echo "  * $res (current)"
          else
            echo "    $res"
          fi
        done

        # Check if current resolution is supported
        if [[ " ${concatStringsSep " " cfg.supportedResolutions} " =~ " $CURRENT_RES " ]]; then
          echo ""
          echo "✓ Current resolution is supported"
          exit 0
        else
          echo ""
          echo "⚠ Current resolution not in supported list"
          exit 2
        fi
      '')

      (writeShellScriptBin "resolution-switcher" ''
        #!/usr/bin/env bash
        # Resolution switcher script for virtual display

        VIRTUAL_DISPLAY="''${VIRTUAL_DISPLAY:-:99}"
        export DISPLAY=$VIRTUAL_DISPLAY

        # Default supported resolutions (fallback if env var not set)
        SUPPORTED_RESOLUTIONS="''${SUPPORTED_RESOLUTIONS:-3840x2160 3440x1440 2560x1440 1920x1080}"

        show_help() {
          echo "Resolution switcher for virtual display"
          echo ""
          echo "Usage: $0 [RESOLUTION|COMMAND]"
          echo ""
          echo "Resolutions:"
          for res in $SUPPORTED_RESOLUTIONS; do
            echo "  $res"
          done
          echo ""
          echo "Commands:"
          echo "  detect    - Detect current resolution"
          echo "  list      - List supported resolutions"
          echo "  current   - Show current resolution"
          echo "  help      - Show this help"
          echo ""
          echo "Examples:"
          echo "  $0 3840x2160    # Switch to 4K"
          echo "  $0 1920x1080    # Switch to 1080p"
          echo "  $0 detect       # Show current resolution"
        }

        detect_current() {
          local current_res
          current_res=$(xrandr --current 2>/dev/null | grep "*" | awk '{print $1}' | head -n1)
          if [ -z "$current_res" ]; then
            echo "Unable to detect current resolution"
            return 1
          fi
          echo "$current_res"
        }

        switch_resolution() {
          local target_res="$1"
          local current_res

          echo "Attempting to switch to $target_res..."

          # Verify target resolution is supported
          if [[ ! " $SUPPORTED_RESOLUTIONS " =~ " $target_res " ]]; then
            echo "Error: Resolution '$target_res' not supported"
            echo "Supported resolutions: $SUPPORTED_RESOLUTIONS"
            exit 1
          fi

          # Get current resolution
          current_res=$(detect_current)
          if [ $? -ne 0 ]; then
            echo "Error: Cannot detect current resolution"
            exit 1
          fi

          echo "Current resolution: $current_res"

          # Check if already at target resolution
          if [ "$current_res" = "$target_res" ]; then
            echo "Already at $target_res - no change needed"
            exit 0
          fi

          # Find the connected virtual display output name
          local output_name
          output_name=$(xrandr --current 2>/dev/null | grep " connected" | awk '{print $1}' | head -n1)

          if [ -z "$output_name" ]; then
            echo "Error: No connected display found"
            exit 1
          fi

          echo "Using display output: $output_name"

          # Attempt to change resolution
          if xrandr --output "$output_name" --mode "$target_res" 2>/dev/null; then
            echo "✓ Successfully switched to $target_res"

            # Verify the change
            sleep 1
            local verify_res
            verify_res=$(detect_current)
            if [ "$verify_res" = "$target_res" ]; then
              echo "✓ Resolution change verified"
              exit 0
            else
              echo "⚠ Warning: Resolution may not have applied correctly"
              echo "Expected: $target_res, Got: $verify_res"
              exit 2
            fi
          else
            echo "✗ Failed to switch to $target_res"
            exit 3
          fi
        }

        list_resolutions() {
          echo "Supported resolutions:"
          local current_res
          current_res=$(detect_current)

          for res in $SUPPORTED_RESOLUTIONS; do
            if [ "$res" = "$current_res" ]; then
              echo "  * $res (current)"
            else
              echo "    $res"
            fi
          done
        }

        # Main logic
        case "$1" in
          "help"|"-h"|"--help"|"")
            show_help
            ;;
          "detect"|"current")
            detect_current
            ;;
          "list")
            list_resolutions
            ;;
          *)
            # Assume it's a resolution
            if [[ "$1" =~ ^[0-9]+x[0-9]+$ ]]; then
              switch_resolution "$1"
            else
              echo "Error: Invalid resolution format '$1'"
              echo "Use format like 3840x2160 or 'help' for usage"
              exit 1
            fi
            ;;
        esac
      '')

      xorg.xrandr
    ];

    # Systemd user service for resolution management
    systemd.user.services.resolution-switcher = {
      description = "Resolution switching service for virtual display";
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = "yes";
        ExecStart = "${pkgs.bash}/bin/bash -c 'echo Resolution switcher service started'";
        Environment = [
          "VIRTUAL_DISPLAY=${cfg.virtualDisplay}"
          "SUPPORTED_RESOLUTIONS=${concatStringsSep " " cfg.supportedResolutions}"
        ];
      };
      wantedBy = ["graphical-session.target"];
    };
  };
}
