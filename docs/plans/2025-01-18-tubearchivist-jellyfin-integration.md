# TubeArchivist + Jellyfin Integration Design

## Overview
Integrate TubeArchivist (self-hosted YouTube media server) with existing Jellyfin setup using full metadata sync approach. TubeArchivist videos will appear in Jellyfin library with rich metadata, search, and app compatibility.

## Architecture

### Components
1. **TubeArchivist Service** - Docker containers for downloading and indexing YouTube content
2. **Jellyfin Plugin** - TubeArchivist-Jellyfin plugin for metadata synchronization
3. **Shared Storage** - Videos accessible to both services via proper mounting
4. **API Integration** - Token-based communication between services

### Directory Structure
```
/srv/media/
├── tubearchivist/          # TubeArchivist data
│   ├── videos/            # Downloaded videos  
│   ├── cache/             # Cache files
│   └── redis/             # Redis data
├── movies/                # Existing Jellyfin content
├── tv/                    # Existing Jellyfin content
└── ...
```

### Network Flow
- TubeArchivist downloads YouTube videos to `/srv/media/tubearchivist/videos`
- Jellyfin plugin reads TubeArchivist API for metadata
- Jellyfin scans `/youtube` mount (pointing to TA videos) for media files
- Plugin enriches Jellyfin library with TubeArchivist metadata

## Implementation Details

### TubeArchivist Docker Configuration
- Use `virtualisation.oci-containers` for deployment
- Redis container for caching
- Persistent volume mounts for data
- Dedicated Docker network
- Environment variables for YouTube API and admin settings

### Jellyfin Plugin Integration
- Install `tubearchivist-jf-plugin` via plugin catalog
- Configure API URL and token
- Mount point mapping: `/youtube` → `/srv/media/tubearchivist/videos`
- Sync intervals and metadata preferences
- Firewall rules for inter-service communication

### Storage & Security
- Extend existing media group to include `tubearchivist` user
- Additional tmpfiles rules for TubeArchivist directories
- Proper permissions on shared storage
- API token secure generation and storage

## Implementation Phases

### Phase 1: TubeArchivist Service
1. Add Docker container configuration to `modules/nixos/services.nix`
2. Create directory structure with systemd tmpfiles
3. Configure environment variables and networking
4. Set up Redis container for caching

### Phase 2: Jellyfin Integration
1. Update Jellyfin configuration to mount YouTube directory
2. Document plugin installation and configuration steps
3. Set up API tokens and service communication
4. Configure firewall rules for inter-service access

### Phase 3: Storage & Security
1. Extend media group permissions for TubeArchivist
2. Create backup strategy for TubeArchivist data
3. Set up logging and monitoring
4. Test integration and validate functionality

## Configuration Files

### Files to Modify
- `modules/nixos/services.nix` - Add TubeArchivist service
- `targets/drlight/default.nix` - Extend media directory structure
- `modules/home-manager/media.nix` - Add TubeArchivist client tools

### New Configuration Options
- TubeArchivist API token configuration
- YouTube API key management
- Plugin sync settings
- Backup configuration

## Success Criteria
- TubeArchivist service runs successfully in Docker
- Jellyfin plugin installs and configures correctly
- YouTube videos appear in Jellyfin with metadata
- Both services can access shared storage
- Integration is stable and maintainable

## Risks & Mitigations
- **Docker complexity**: Use well-documented container configuration
- **Plugin compatibility**: Test with current Jellyfin version
- **Storage permissions**: Careful group and permission management
- **API rate limits**: Proper YouTube API quota management

## Timeline
- Phase 1: TubeArchivist service setup (1-2 hours)
- Phase 2: Jellyfin plugin integration (1 hour)
- Phase 3: Testing and validation (30 minutes)
- Total: ~3-4 hours for complete implementation