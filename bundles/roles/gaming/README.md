# Gaming Bundle

The gaming bundle provides tools and applications for gaming and entertainment.

## Purpose

This bundle is designed for gaming systems and includes:

- Gaming platforms
- Entertainment applications
- Gaming utilities

## Included Categories

### Gaming Platforms
- Steam (via platform-specific bundles)
- Gaming applications

### Entertainment
- Media applications
- Streaming tools

## Usage

```nix
imports = [
  ./bundles/roles/gaming
];
```

## Notes

Most gaming applications are platform-specific and are included in the respective platform bundles (`bundles/platforms/darwin/` or `bundles/platforms/linux/`). This bundle serves as a placeholder for cross-platform gaming tools.