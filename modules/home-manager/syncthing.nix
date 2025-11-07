{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.myConfig.syncthing;
in {
  options.myConfig.syncthing = {
    enable = mkOption {
      type = types.bool;
      default = false;
      description = "Enable Syncthing file synchronization service";
    };

    gui = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enable Syncthing web GUI";
      };
      port = mkOption {
        type = types.port;
        default = 8384;
        description = "Port for Syncthing web GUI";
      };
      address = mkOption {
        type = types.str;
        default = "127.0.0.1";
        description = "Address to bind GUI to (127.0.0.1 for localhost only)";
      };
      user = mkOption {
        type = types.str;
        default = "";
        description = "GUI username (empty for no auth)";
      };
      password = mkOption {
        type = types.str;
        default = "";
        description = "GUI password (empty for no auth)";
      };
    };

    folders = mkOption {
      type = types.attrsOf (types.submodule {
        options = {
          path = mkOption {
            type = types.str;
            description = "Local path to sync";
          };
          id = mkOption {
            type = types.str;
            description = "Unique folder ID";
          };
          label = mkOption {
            type = types.str;
            default = "";
            description = "Human-readable folder label";
          };
          devices = mkOption {
            type = types.listOf types.str;
            default = [];
            description = "List of device IDs to sync with";
          };
          ignorePerms = mkOption {
            type = types.bool;
            default = true;
            description = "Ignore permission changes when syncing";
          };
          versioning = {
            type = mkOption {
              type = types.enum ["none" "simple" "staggered" "trashcan"];
              default = "simple";
              description = "Versioning strategy";
            };
            params = mkOption {
              type = types.attrs;
              default = {};
              description = "Versioning parameters";
            };
          };
        };
      });
      default = {};
      description = "Syncthing folder configurations";
    };

    devices = mkOption {
      type = types.attrsOf (types.submodule {
        options = {
          id = mkOption {
            type = types.str;
            description = "Device ID";
          };
          name = mkOption {
            type = types.str;
            description = "Device name";
          };
          addresses = mkOption {
            type = types.listOf types.str;
            default = [];
            description = "Device addresses for direct connection";
          };
          compression = mkOption {
            type = types.enum ["always" "never" "metadata"];
            default = "metadata";
            description = "Compression level";
          };
          introducer = mkOption {
            type = types.bool;
            default = false;
            description = "Allow this device to introduce other devices";
          };
        };
      });
      default = {};
      description = "Syncthing device configurations";
    };

    extraOptions = mkOption {
      type = types.attrs;
      default = {};
      description = "Additional Syncthing configuration options";
    };
  };

  config = mkIf cfg.enable {
    services.syncthing = {
      enable = true;
      user = config.home.username;
      dataDir = config.xdg.configHome + "/syncthing";

      # GUI Configuration
      guiAddress = cfg.gui.address + ":" + toString cfg.gui.port;
      guiApiKey =
        mkIf (cfg.gui.user != "" && cfg.gui.password != "")
        (builtins.hashString "sha256" (cfg.gui.user + ":" + cfg.gui.password));

      # Folder Configuration with defaults
      folders = mkMerge [
        cfg.folders
        {
          # Default folders if none specified
          "Documents" = mkIf (cfg.folders == {}) {
            path = config.home.homeDirectory + "/Documents";
            id = "documents";
            devices = [];
            ignorePerms = true;
            versioning = {
              type = "staggered";
              params = {
                maxAge = "86400"; # 24 hours
                versionsPath = ".stversions";
              };
            };
          };

          "Desktop" = mkIf (cfg.folders == {}) {
            path = config.home.homeDirectory + "/Desktop";
            id = "desktop";
            devices = [];
            ignorePerms = true;
          };

          "Downloads" = mkIf (cfg.folders == {}) {
            path = config.home.homeDirectory + "/Downloads";
            id = "downloads";
            devices = [];
            ignorePerms = true;
          };
        }
      ];

      # Device Configuration
      inherit devices;

      # Cross-platform settings
      systemService = !pkgs.stdenv.isDarwin; # Use system service on Linux

      # Security settings
      extraOptions = mkMerge [
        cfg.extraOptions
        {
          options = {
            globalAnnounce = false; # Disable global discovery
            localAnnounce = true; # Enable local discovery
            urAccepted = -1; # Auto-accept usage reporting
          };
        }
      ];
    };

    # Ensure data directory exists
    home.activation.createSyncthingDir = lib.hm.dag.entryAfter ["writeBoundary"] ''
      $DRY_RUN_CMD mkdir -p ${config.xdg.configHome}/syncthing
    '';

    # Create .stignore files for default folders
    home.activation.setupSyncthingIgnores = lib.hm.dag.entryAfter ["writeBoundary"] ''
            # Create .stignore files for each folder
            for folder in Documents Desktop Downloads; do
              folder_path="${config.home.homeDirectory}/$folder"
              ignore_file="$folder_path/.stignore"
              if [[ -d "$folder_path" && ! -f "$ignore_file" ]]; then
                $DRY_RUN_CMD cat > "$ignore_file" << 'EOF'
      # Common ignore patterns
      *.tmp
      *.temp
      .DS_Store
      Thumbs.db
      desktop.ini
      node_modules/
      .git/
      .cache/
      *.log
      EOF
              fi
            done
    '';
  };
}
