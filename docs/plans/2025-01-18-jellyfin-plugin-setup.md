# TubeArchivist + Jellyfin Plugin Setup Guide

## Overview
This guide walks through installing and configuring the TubeArchivist Jellyfin plugin to sync YouTube metadata and videos into your Jellyfin library.

## Prerequisites
- TubeArchivist service running (configured in Nix)
- Jellyfin server running on the same system
- Admin access to Jellyfin web interface

## Plugin Installation

### Step 1: Install TubeArchivist-Jellyfin Plugin
1. Open Jellyfin web interface
2. Navigate to **Dashboard → Plugins → Catalog**
3. Search for "TubeArchivist" or "tubearchivist-jf-plugin"
4. Click **Install** on the TubeArchivist plugin
5. Wait for installation to complete
6. Restart Jellyfin server if prompted

### Step 2: Configure Plugin Settings
1. Navigate to **Dashboard → Plugins → TubeArchivist**
2. Configure the following settings:

#### Basic Configuration
- **TubeArchivist URL**: `http://localhost:8000`
- **TubeArchivist API Token**: Generate from TubeArchivist admin panel
- **Jellyfin Token**: Generate from Jellyfin dashboard

#### Generate TubeArchivist API Token
1. Access TubeArchivist web interface at `http://localhost:8000`
2. Login as admin
3. Navigate to **Settings → API**
4. Create new API token
5. Copy token for plugin configuration

#### Generate Jellyfin API Token
1. In Jellyfin, go to **Dashboard → API Keys**
2. Click **+ Add API Key**
3. Name it "TubeArchivist Plugin"
4. Copy generated token

#### Advanced Settings
- **Sync Interval**: 30 minutes (recommended)
- **Import Playlists**: Enable
- **Import Subtitles**: Enable
- **Import Comments**: Disable (optional)
- **Metadata Refresh**: Weekly

### Step 3: Media Library Configuration
1. In Jellyfin, add a new media library:
   - **Content Type**: "Shows" or "Mixed"
   - **Folders**: `/youtube` (TubeArchivist mount point)
   - **Enable real-time monitoring**: On

2. Set library metadata provider:
   - **Primary**: TubeArchivist Plugin
   - **Fallback**: TheMovieDB (optional)

## Post-Setup Tasks

### Verify Integration
1. Add some YouTube videos to TubeArchivist
2. Trigger manual sync in plugin settings
3. Verify videos appear in Jellyfin library
4. Check metadata (titles, descriptions, thumbnails)

### Optional: Configure Reverse Proxy
For external access, configure your reverse proxy to route:
- `/jellyfin` → Jellyfin server
- `/tubearchivist` → TubeArchivist server

### Troubleshooting

#### Plugin Not Finding Videos
- Check `/youtube` mount is accessible
- Verify TubeArchivist has downloaded videos
- Check file permissions on video directories

#### Sync Not Working
- Verify API tokens are valid
- Check network connectivity between services
- Review plugin logs in Jellyfin

#### Missing Metadata
- Ensure TubeArchivist has indexed videos
- Check plugin sync settings
- Verify TubeArchivist API accessibility

## Automation
Consider setting up systemd timers for:
- Regular TubeArchivist container health checks
- Jellyfin library scans
- Backup of TubeArchivist database

## Security Notes
- Keep API tokens secure and rotate regularly
- Restrict network access if services are exposed externally
- Regular updates of TubeArchivist and plugin versions