# Multi-Session Display Setup Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Create Wayland compositor session for physical monitor + virtual X11 display for streaming with independent Sunshine instances

**Architecture:** Physical monitor uses GNOME/KDE Wayland session while virtual X11 server with NVIDIA acceleration handles streaming, enabling both displays to operate simultaneously

**Tech Stack:** xorg-server, nvidia-drm, systemd-user services, udev rules, Sunshine configuration

### Task 1: Create Virtual Display Service

**Files:**
- Create: `modules/nixos/virtual-display.nix`
- Modify: `targets/zero/default.nix:98-105`

**Step 1: Write virtual display module**

```nix
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.virtual-display;
in {
  options.services.virtual-display = {
    enable = mkEnableOption "Enable virtual display server";
    resolution = mkOption {
      type = types.str;
      default = "3840x2160";
      description = "Virtual display resolution";
    };
    user = mkOption {
      type = types.str;
      default = "monkey";
      description = "User to run virtual display as";
    };
  };

  config = mkIf cfg.enable {
    # Virtual display server package
    environment.systemPackages = with pkgs; [
      xorg.xorgserver
      xorg.xrandr
    ];

    # Systemd user service for virtual display
    systemd.user.services.virtual-display = {
      description = "Virtual display server for streaming";
      serviceConfig = {
        Type = "simple";
        ExecStart = "${pkgs.xorg.xorgserver}/bin/Xorg -noreset +extension GLX +extension RANDR +extension RENDER -logfile /tmp/vdisplay.log :99";
        Restart = "on-failure";
        Environment = "DISPLAY=:99";
      };
      wantedBy = [ "graphical-session.target" ];
    };
  };
}
```

**Step 2: Add import to zero configuration**

**Step 3: Test virtual display service**

**Step 4: Configure virtual display module**

**Step 5: Commit virtual display service**

```bash
git add modules/nixos/virtual-display.nix targets/zero/default.nix
git commit -m "feat: add virtual display service module"
```

### Task 2: Create Display Switcher Scripts

**Files:**
- Create: `modules/nixos/scripts/display-switcher.nix`
- Create: `modules/nixos/scripts/monitor-detect.nix`

**Step 1: Write monitor detection script**

```bash
#!/usr/bin/env bash
# Detect connected displays
xrandr --query monitors | grep " connected" | wc -l
```

**Step 2: Write display switcher script**

**Step 3: Test detection script**

**Step 4: Test switcher script**

**Step 5: Commit display scripts**

```bash
git add modules/nixos/scripts/display-switcher.nix modules/nixos/scripts/monitor-detect.nix
git commit -m "feat: add display detection and switching scripts"
```

### Task 3: Configure Sunshine Service for Virtual Display

**Files:**
- Modify: `targets/zero/default.nix:89-98`

**Step 1: Update Sunshine configuration**

```nix
services.sunshine = {
  enable = true;
  autoStart = true;
  capSysAdmin = true;
  openFirewall = true;
  settings = {
    origin_web_ui_allowed = "wan";
    display = ":99"; # Use virtual display
  };
  package = pkgs.unstable.sunshine;
};
```

**Step 2: Add physical monitor detection**

**Step 3: Test Sunshine with virtual display**

**Step 4: Verify streaming works**

**Step 5: Commit Sunshine config**

```bash
git add targets/zero/default.nix
git commit -m "feat: configure Sunshine for virtual display streaming"
```

### Task 4: Create Dynamic Resolution Switching

**Files:**
- Create: `modules/nixos/scripts/resolution-switcher.nix`
- Modify: `targets/zero/default.nix:105-115`

**Step 1: Write resolution detection script**

**Step 2: Write resolution switcher script**

**Step 3: Add systemd service for resolution switching**

**Step 4: Test resolution switching**

**Step 5: Commit resolution switcher**

```bash
git add modules/nixos/scripts/resolution-switcher.nix targets/zero/default.nix
git commit -m "feat: add dynamic resolution switching"
```

### Task 5: Add Physical Monitor Detection

**Files:**
- Create: `modules/nixos/hardware/monitor-detect.nix`
- Modify: `targets/zero/default.nix:30-35`

**Step 1: Write udev rules for monitor hotplug**

**Step 2: Create monitor state service**

**Step 3: Test hotplug detection**

**Step 4: Verify virtual display toggles**

**Step 5: Commit monitor detection**

```bash
git add modules/nixos/hardware/monitor-detect.nix targets/zero/default.nix
git commit -m "feat: add physical monitor hotplug detection"
```

### Task 6: Final Integration and Testing

**Files:**
- Modify: `targets/zero/default.nix` (entire file)
- Create: `docs/zero-multi-display-setup.md`

**Step 1: Integrate all modules**

**Step 2: Add documentation**

**Step 3: Test complete system**

**Step 4: Performance validation**

**Step 5: Final commit and documentation**

```bash
git add targets/zero/default.nix docs/zero-multi-display-setup.md
git commit -m "feat: complete multi-session display setup integration"
```

## Testing Strategy

**Verify:**
- Virtual display starts without physical monitor
- Physical monitor works normally when connected
- Sunshine streams from virtual display when headless
- Resolution switching works for different clients
- Both displays can run simultaneously

**Commands:**
```bash
# Test virtual display
systemctl --user start virtual-display
export DISPLAY=:99
glxinfo | grep "OpenGL renderer"

# Test streaming
sunshine --version
systemctl --user status sunshine

# Test resolution switching
./modules/nixos/scripts/resolution-switcher.sh 3840x2160
./modules/nixos/scripts/resolution-switcher.sh 3440x1440
```

## Rollback Plan

If issues occur:
```bash
# Disable virtual display
sudo nixos-rebuild switch --rollback
# Remove virtual display service
# Revert to single Sunshine instance
```