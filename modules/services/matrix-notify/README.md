# Notification Router

A multi-backend notification system with HTTP RPC routing for agent-to-agent communication.

## Overview

The notification router provides a unified interface for sending notifications across multiple backends (Matrix, ntfy) via a simple HTTP API. It runs as a service on both NixOS and macOS (Darwin).

## Quick Start

### 1. Enable the module

```nix
{
  myConfig.notify = {
    enable = true;
    port = 18080;  # HTTP API port
    defaultBackend = "matrix";
    
    backends.matrix = {
      enable = true;
      homeserver = "https://matrix.tchncs.de";
      roomId = "!your-room-id:matrix.tchncs.de";
      accessTokenFile = "/run/secrets/matrix-token";
    };
  };
}
```

### 2. Import the modules

**Base module (required on all platforms):**
```nix
{
  imports = [
    ./modules/services/matrix-notify  # Provides scripts and options
  ];
}
```

**Platform-specific service (for auto-start):**

NixOS:
```nix
{
  imports = [
    ./modules/services/matrix-notify/nixos.nix  # Auto-starts with systemd
  ];
}
```

Darwin (macOS):
```nix
{
  imports = [
    ./modules/services/matrix-notify/darwin.nix  # Auto-starts with launchd
  ];
}
```

### 3. Get Matrix Access Token

1. Open Element (web or app)
2. Go to Settings → Help & About
3. Click "Access Token" to reveal your token
4. Save it to a file (e.g., `/run/secrets/matrix-token`)

## Usage

### Via HTTP API

```bash
# Send a notification
curl -X POST http://localhost:18080/notify \
  -H "Content-Type: application/json" \
  -d '{
    "message": "Build completed successfully!",
    "backend": "matrix",
    "priority": "normal"
  }'

# Health check
curl http://localhost:18080/health
```

### Via Client Script

```bash
# Simple notification
notify-send "Task completed"

# With backend override
notify-send "Urgent alert" matrix

# Full syntax
notify-send "message" [backend] [room] [priority]
```

### From Scripts/Agents

```bash
#!/bin/bash
# Agent notification example

# Send completion notification
echo "Analysis complete for repo XYZ" | notify-send

# Send error notification
notify-send "Build failed" matrix "" high
```

## Configuration Options

```nix
myConfig.notify = {
  enable = true;
  port = 18080;                          # HTTP API port
  defaultBackend = "matrix";             # Default: "matrix" or "ntfy"
  
  backends = {
    matrix = {
      enable = true;
      homeserver = "https://matrix.tchncs.de";
      roomId = "!room:server.com";       # Default room
      accessTokenFile = "/path/to/token";
    };
    
    ntfy = {
      enable = true;
      server = "https://ntfy.sh";        # Or your self-hosted server
      topic = "your-secret-topic";       # Like a password - keep it secret
    };
  };
  
  # Routing rules (optional)
  routes = [
    { name = "alerts"; backend = "matrix"; match = "priority:high"; }
  ];
};
```

## API Reference

### POST /notify

Send a notification.

**Request Body:**
```json
{
  "message": "Notification text",
  "backend": "matrix",      // Optional: "matrix" or "ntfy"
  "room": "!room:server",   // Optional: override default room/topic
  "format": "text",         // Optional: "text" or "html"
  "priority": "normal"      // Optional: "low", "normal", "high", "urgent"
}
```

**Response:**
```json
{"status": "sent"}
```

### GET /health

Health check endpoint.

**Response:**
```json
{"status": "ok"}
```

## Architecture

```
┌─────────────┐     HTTP      ┌─────────────────┐
│   Agent     │ ─────────────→│  notify-router  │
│  (Client)   │   POST /notify│    (Service)    │
└─────────────┘               └────────┬────────┘
                                       │
                          ┌────────────┼────────────┐
                          │            │            │
                          ▼            ▼            ▼
                   ┌──────────┐  ┌──────────┐  ┌──────────┐
                   │  Matrix  │  │   ntfy   │  │  (more)  │
                   └──────────┘  └──────────┘  └──────────┘
```

## Security Notes

- **Access Tokens**: Store Matrix access tokens securely (e.g., in 1Password, opnix)
- **ntfy Topics**: Treat ntfy topics like passwords - anyone with the topic can subscribe
- **Firewall**: The service listens on localhost by default; open firewall only if needed
- **Encryption**: Messages sent to Matrix are encrypted in transit (HTTPS). For E2EE rooms, you'll need additional setup.

## Troubleshooting

### Service won't start

Check logs:
- **NixOS**: `journalctl -u notify-router -f`
- **Darwin**: `tail -f /tmp/notify-router.log`

### Matrix notifications not sending

1. Verify access token: `cat /path/to/token`
2. Check room ID format: `!room:server.com`
3. Test manually with curl (see Matrix API docs)

### Port already in use

Change the port in configuration:
```nix
myConfig.notify.port = 18081;  # Use a different port
```

## Future Enhancements

- [ ] Webhook support (receive notifications from external services)
- [ ] Message queue for reliability
- [ ] More backends (Slack, Discord, Pushover)
- [ ] E2EE support for Matrix
- [ ] Web UI for configuration
