# Zero Multi-Display Setup Guide

## Overview

This document describes the multi-session display setup for the `zero` NixOS system, which enables simultaneous operation of physical monitors and a virtual display for game streaming via Sunshine.

## Architecture

The system uses a dual-display architecture:

- **Physical Display**: KDE Plasma Wayland session on connected monitors
- **Virtual Display**: X11 server running on display :99 for Sunshine streaming

This allows:
- Gaming on the physical monitor when connected
- Headless streaming from the virtual display when no physical monitor is present
- Independent resolution management for each display
- Seamless switching between configurations

## Components

### 1. Virtual Display Service (`virtual-display.nix`)

**Purpose**: Manages a headless X11 server for streaming
**Display**: :99
**Resolution**: 3840x2160 (configurable)
**User**: monkey

**Service**: `systemd --user virtual-display`

```bash
# Manual control
systemctl --user start virtual-display
systemctl --user stop virtual-display
systemctl --user status virtual-display

# Check logs
journalctl --user -u virtual-display
```

### 2. Physical Monitor Detection (`monitor-detect.nix`)

**Purpose**: Detects physical monitor hotplug events via udev
**Automatic**: Enables/disables virtual display based on monitor state
**User**: monkey

**Features**:
- Monitor hotplug detection
- Automatic service management
- State tracking

### 3. Display Switcher Scripts (`display-switcher.nix`)

**Purpose**: Provides utilities for manual display management
**Location**: `/run/current-system/sw/bin/display-switcher*`

**Available scripts**:
- `display-switcher.sh` - Manual display switching
- `monitor-detect.sh` - Check connected monitors
- `virtual-displayctl` - Virtual display control

### 4. Resolution Switcher (`resolution-switcher.nix`)

**Purpose**: Dynamic resolution management for streaming
**Supported Resolutions**:
- 3840x2160 (4K)
- 3440x1440 (UWQHD)
- 2560x1440 (QHD)
- 1920x1080 (FHD)

**Usage**:
```bash
# Switch resolution
resolution-switcher.sh 3840x2160
resolution-switcher.sh 3440x1440

# List available resolutions
resolution-switcher.sh --list
```

### 5. Sunshine Configuration

**Purpose**: Game streaming from virtual display
**Package**: unstable.sunshine
**Display**: :99 (virtual)
**Web UI**: WAN access enabled

**Configuration**:
```nix
services.sunshine = {
  enable = true;
  autoStart = true;
  capSysAdmin = true;
  openFirewall = true;
  settings = {
    origin_web_ui_allowed = "wan";
    display = ":99";
  };
};
```

## Usage Scenarios

### Scenario 1: Headless Streaming

1. **System boots without physical monitor**
2. **Virtual display automatically starts** on :99
3. **Sunshine streams from virtual display** at 4K
4. **Clients connect remotely** for gaming

### Scenario 2: Physical Monitor Connected

1. **Physical monitor detected** via udev
2. **KDE Plasma Wayland session** runs on physical display
3. **Virtual display continues running** for streaming
4. **Dual-display operation** available

### Scenario 3: Manual Control

1. **Override automatic behavior** with scripts
2. **Force virtual display on/off** as needed
3. **Switch resolutions** for different clients
4. **Debug issues** with manual commands

## Commands and Operations

### System Status

```bash
# Check virtual display status
systemctl --user status virtual-display

# Check Sunshine status
systemctl --user status sunshine

# List connected monitors
xrandr --query | grep " connected"

# Check virtual display
export DISPLAY=:99
glxinfo | grep "OpenGL renderer"
```

### Manual Display Control

```bash
# Start virtual display manually
systemctl --user start virtual-display

# Stop virtual display manually
systemctl --user stop virtual-display

# Switch to specific resolution
resolution-switcher.sh 3440x1440

# Check monitor state
monitor-detect.sh
```

### Streaming Operations

```bash
# Test Sunshine
sunshine --version

# Check streaming logs
journalctl --user -u sunshine

# Access web UI (default: 47984)
# http://localhost:47984
```

## Configuration Files

### Main Configuration
- `/etc/nixos/targets/zero/default.nix` - System integration

### Modules
- `/etc/nixos/modules/nixos/virtual-display.nix` - Virtual display service
- `/etc/nixos/modules/nixos/hardware/monitor-detect.nix` - Monitor detection
- `/etc/nixos/modules/nixos/scripts/display-switcher.nix` - Display utilities
- `/etc/nixos/modules/nixos/scripts/resolution-switcher.nix` - Resolution management

### Service Files
- `~/.config/systemd/user/virtual-display.service` - User service
- Udev rules in `/run/udev/rules.d/` for monitor detection

## Troubleshooting

### Virtual Display Issues

**Problem**: Virtual display won't start
**Solutions**:
```bash
# Check service status
systemctl --user status virtual-display

# Check logs
journalctl --user -u virtual-display -f

# Manual start for debugging
Xorg -noreset +extension GLX +extension RANDR +extension RENDER -logfile /tmp/vdisplay.log :99
```

**Problem**: No OpenGL acceleration
**Solutions**:
```bash
# Check NVIDIA driver
nvidia-smi

# Check OpenGL on virtual display
export DISPLAY=:99
glxinfo | grep "OpenGL renderer"
glxgears -info
```

### Sunshine Issues

**Problem**: Sunshine can't access display
**Solutions**:
```bash
# Verify virtual display running
systemctl --user status virtual-display

# Check Sunshine config
cat ~/.config/sunshine/sunshine.conf

# Restart Sunshine
systemctl --user restart sunshine
```

**Problem**: Streaming quality issues
**Solutions**:
```bash
# Lower resolution
resolution-switcher.sh 1920x1080

# Check network
iperf3 -c target_ip

# Monitor performance
htop
nvidia-smi
```

### Monitor Detection Issues

**Problem**: Monitor not detected
**Solutions**:
```bash
# Check udev events
udevadm monitor --environment

# Manual detection
xrandr --query

# Check monitor state
monitor-detect.sh
```

## Performance Optimization

### Network Configuration

**Recommended**:
- Wired Ethernet for streaming
- QoS for streaming traffic
- Port forwarding for Sunshine (47984, 47989-48000)

### System Resources

**Monitoring**:
```bash
# GPU usage
nvidia-smi

# CPU usage
htop

# Memory usage
free -h

# Network usage
iftop
```

### Streaming Quality

**Optimizations**:
- Use appropriate resolution for bandwidth
- Enable hardware acceleration
- Configure Sunshine encoder settings
- Monitor latency and bitrate

## Security Considerations

### Network Access

- Sunshine web UI configured for WAN access
- Firewall rules automatically configured
- Consider VPN access for additional security
- Use strong authentication credentials

### Service Isolation

- Virtual display runs as user service
- No elevated privileges required
- Isolated from system display server

## Maintenance

### Updates

After NixOS configuration changes:
```bash
# Rebuild and switch
sudo nixos-rebuild switch

# Restart services if needed
systemctl --user restart virtual-display
systemctl --user restart sunshine
```

### Log Management

```bash
# Clean logs
journalctl --user --vacuum-time=7d

# Monitor log sizes
journalctl --user --disk-usage
```

### Backup Configuration

```bash
# Export current configuration
cp -r /etc/nixos ~/nixos-backup/

# Document custom settings
# (this file serves as documentation)
```

## Integration with Other Services

### Tailscale

- System automatically connects to Tailscale
- Sunshine accessible via Tailscale network
- Remote management through VPN

### Steam/Gaming

- Steam integration with Gamescope
- GameMode enabled for performance
- Controller support with xpadneo

### Audio

- PipeWire audio server
- Audio routing to virtual display possible
- Bluetooth audio support available

## Future Enhancements

Potential improvements:
- Multiple virtual displays
- Automatic resolution selection based on client
- GPU pass-through for virtual displays
- Integration with display manager switching
- Advanced power management for headless operation