# Syncthing Configuration Implementation Specification

## Overview
This specification outlines a comprehensive plan to fully configure Syncthing file synchronization in the Nix configuration system. The implementation will provide cross-platform support (macOS via nix-darwin and Linux via NixOS) with modular, reusable configurations.

## Current State Analysis
- ✅ Syncthing is enabled in `modules/home-manager/development.nix`
- ❌ No configuration options defined
- ❌ No folder/device setup
- ❌ No GUI access configuration
- ❌ No firewall rules
- ❌ No cross-platform optimization

## Implementation Plan

### Phase 1: Core Configuration (High Priority)

#### 1.1 Add Syncthing Options to `modules/common/options.nix`

**Objective**: Define a comprehensive configuration schema for Syncthing settings.

**Specification**:
```nix
# Add to myConfig options
syncthing = {
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
```

#### 1.2 Enhance Home-Manager Config in `modules/home-manager/development.nix`

**Objective**: Update existing Syncthing enable to use new options system.

**Specification**:
```nix
# Replace simple enable with conditional configuration
services.syncthing = lib.mkIf config.myConfig.syncthing.enable {
  enable = true;

  # GUI Configuration
  guiAddress = config.myConfig.syncthing.gui.address + ":" + toString config.myConfig.syncthing.gui.port;
  user = config.myConfig.syncthing.gui.user;
  password = config.myConfig.syncthing.gui.password;

  # Folder Configuration
  folders = config.myConfig.syncthing.folders;

  # Device Configuration
  devices = config.myConfig.syncthing.devices;

  # Extra Options
  extraOptions = config.myConfig.syncthing.extraOptions;
};
```

### Phase 2: Modular Architecture (Medium Priority)

#### 2.1 Create Dedicated Module `modules/home-manager/syncthing.nix`

**Objective**: Create reusable Syncthing configuration module.

**Specification**:
```nix
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.myConfig.syncthing;
in {
  options.myConfig.syncthing = {
    # [Options from Phase 1.1]
  };

  config = mkIf cfg.enable {
    services.syncthing = {
      enable = true;
      user = config.home.username;
      dataDir = config.xdg.configHome + "/syncthing";

      # GUI Configuration
      guiAddress = cfg.gui.address + ":" + toString cfg.gui.port;
      guiApiKey = mkIf (cfg.gui.user != "" && cfg.gui.password != "")
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
          };
        }
      ];

      # Device Configuration
      devices = cfg.devices;

      # Cross-platform settings
      systemService = !pkgs.stdenv.isDarwin; # Use system service on Linux

      # Extra Options
      extraOptions = cfg.extraOptions;
    };

    # Ensure data directory exists
    home.activation.createSyncthingDir = lib.hm.dag.entryAfter ["writeBoundary"] ''
      $DRY_RUN_CMD mkdir -p ${config.xdg.configHome}/syncthing
    '';
  };
}
```

#### 2.2 NixOS System Service in `modules/nixos/services.nix`

**Objective**: Add system-level Syncthing service for Linux systems.

**Specification**:
```nix
# Add to existing services.nix
services.syncthing = mkIf config.myConfig.syncthing.enable {
  enable = true;
  user = config.myConfig.users.primary.name;
  dataDir = "/home/${config.myConfig.users.primary.name}/.config/syncthing";
  configDir = "/home/${config.myConfig.users.primary.name}/.config/syncthing";

  # GUI Configuration
  guiAddress = config.myConfig.syncthing.gui.address + ":" + toString config.myConfig.syncthing.gui.port;

  # Override default folders with user config
  overrideFolders = false;
  overrideDevices = false;

  # Open firewall for sync traffic
  openDefaultPorts = true;

  # Extra Options
  extraOptions = config.myConfig.syncthing.extraOptions;
};

# Firewall configuration
networking.firewall = mkIf config.myConfig.syncthing.enable {
  allowedTCPPorts = [
    config.myConfig.syncthing.gui.port  # GUI
    22000  # Sync protocol
  ];
  allowedUDPPorts = [
    21027  # Discovery
  ];
};
```

### Phase 3: Integration & Security (Medium Priority)

#### 3.1 Bundle Integration

**Objective**: Add Syncthing to appropriate bundles.

**Specification**:
- **Developer Role** (`bundles/roles/developer/default.nix`): Add syncthing package
- **Base Packages** (`bundles/base/default.nix`): Consider adding for all systems
- **Platform-specific**: Ensure package availability on both Darwin and Linux

#### 3.2 Security Configuration

**Objective**: Configure proper security settings.

**Specification**:
```nix
# In syncthing module
services.syncthing = {
  # GUI security
  guiAddress = "127.0.0.1:8384"; # Localhost only
  guiApiKey = mkIf (cfg.gui.user != "" && cfg.gui.password != "")
    (builtins.hashString "sha256" (cfg.gui.user + ":" + cfg.gui.password));

  # Folder permissions
  extraOptions = {
    options = {
      globalAnnounce = false; # Disable global discovery
      localAnnounce = true;   # Enable local discovery
      urAccepted = -1;        # Auto-accept usage reporting
    };
  };
};
```

### Phase 4: Advanced Features (Medium Priority)

#### 4.1 Sync Folders Setup

**Objective**: Configure standard sync folders with ignore patterns.

**Specification**:
```nix
# Default folder configurations
folders = {
  "Documents" = {
    path = config.home.homeDirectory + "/Documents";
    id = "documents";
    devices = [ "device1" "device2" ];
    ignorePerms = true;
    versioning = {
      type = "staggered";
      params = {
        maxAge = "86400";  # 24 hours
        versionsPath = ".stversions";
      };
    };
  };

  "Desktop" = {
    path = config.home.homeDirectory + "/Desktop";
    id = "desktop";
    devices = [ "device1" ];
  };

  "Downloads" = {
    path = config.home.homeDirectory + "/Downloads";
    id = "downloads";
    devices = [ "device1" ];
  };
};

# Create ignore files
home.activation.setupSyncthingIgnores = lib.hm.dag.entryAfter ["writeBoundary"] ''
  # Create .stignore files for each folder
  for folder in Documents Desktop Downloads; do
    ignore_file="${config.home.homeDirectory}/$folder/.stignore"
    if [[ ! -f "$ignore_file" ]]; then
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
```

#### 4.2 Device Management

**Objective**: Configure device connections and discovery.

**Specification**:
```nix
# Device configuration example
devices = {
  "laptop" = {
    id = "LAPTOP-DEVICE-ID";
    name = "Personal Laptop";
    addresses = [ "tcp://192.168.1.100:22000" ];
    compression = "always";
    introducer = false;
  };

  "desktop" = {
    id = "DESKTOP-DEVICE-ID";
    name = "Home Desktop";
    addresses = [ "tcp://192.168.1.101:22000" ];
    compression = "metadata";
    introducer = true;
  };

  "server" = {
    id = "SERVER-DEVICE-ID";
    name = "Backup Server";
    addresses = [ "tcp://server.example.com:22000" ];
    compression = "always";
    introducer = false;
  };
};
```

### Phase 5: Testing & Validation (High Priority)

#### 5.1 Cross-Platform Testing

**Objective**: Ensure configuration works on both macOS and Linux.

**Test Cases**:
1. **macOS (Darwin)**:
   - Home-manager configuration only
   - GUI accessible at localhost:8384
   - Folder sync working
   - No system service conflicts

2. **Linux (NixOS)**:
   - Combined home-manager + system service
   - System service running as user
   - Firewall rules active
   - GUI accessible
   - Folder permissions correct

**Validation Commands**:
```bash
# Check service status
systemctl status syncthing@$USER  # Linux
launchctl list | grep syncthing   # macOS

# Check GUI access
curl -I http://localhost:8384

# Check configuration
syncthing --paths
syncthing cli config dump
```

#### 5.2 Configuration Testing

**Test Scenarios**:
- Enable/disable functionality
- Folder addition/removal
- Device pairing/unpairing
- GUI authentication
- Sync conflict resolution
- Versioning behavior

### Implementation Order

1. **Phase 1**: Establish configuration foundation
2. **Phase 2**: Create modular architecture
3. **Phase 3**: Integrate with existing bundles
4. **Phase 4**: Add advanced features
5. **Phase 5**: Comprehensive testing

### Dependencies

- `services.syncthing` (home-manager)
- `services.syncthing` (nixos)
- Firewall configuration (nixos)
- User management integration

### Security Considerations

- GUI bound to localhost only
- Optional authentication
- Firewall rules for sync traffic
- Folder permission isolation
- No global discovery by default

### Files to Modify

1. `modules/common/options.nix` - Add syncthing options
2. `modules/home-manager/development.nix` - Update existing config
3. `modules/home-manager/syncthing.nix` - New dedicated module
4. `modules/nixos/services.nix` - Add system service
5. `bundles/roles/developer/default.nix` - Add package
6. `bundles/base/default.nix` - Consider adding package

### Testing Checklist

- [ ] Configuration builds without errors
- [ ] GUI accessible on both platforms
- [ ] Folder sync works between devices
- [ ] Firewall rules active on Linux
- [ ] Service starts automatically
- [ ] Configuration persists across rebuilds
- [ ] Security settings applied correctly

This specification provides a complete blueprint for implementing Syncthing configuration in your Nix setup. Each phase builds upon the previous one, ensuring a robust and maintainable configuration.