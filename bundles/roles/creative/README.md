# Creative Bundle

The creative bundle provides tools for media creation, content production, and knowledge management.

## Purpose

This bundle supports creative workflows including:

- Media processing and editing
- Note-taking and knowledge management
- Content creation tools

## Included Categories

### Media Processing
- `ffmpeg` - Video/audio processing
- `imagemagick` - Image manipulation



### Content Creation
- `glow` - Markdown renderer
- `pandoc` - Document converter

## Usage

```nix
imports = [
  ./bundles/roles/creative
];
```

## Notes

This bundle works with `modules/home-manager/media.nix` for additional media-related configuration.