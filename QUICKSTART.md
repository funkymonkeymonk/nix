# Cattle Quick Reference

## Status: ✅ Ready to Test

Your flake now has both old (pets) and new (cattle) configurations side-by-side.

## Available Configurations

```bash
# Old configs (pets - impure)
nix build .#nixosConfigurations.zero.config.system.build.toplevel

# New configs (cattle - pure)
nix build .#nixosConfigurations.type-desktop.config.system.build.toplevel
nix build .#nixosConfigurations.type-server.config.system.build.toplevel
```

## Interactive TUI Installation

The installer features a beautiful ncurses-style TUI powered by [gum](https://github.com/charmbracelet/gum).

### Quick Install
```bash
# 1. Boot NixOS USB on target
# 2. Set password: passwd
# 3. Get IP: ip addr show

# 4. From your Mac - just run:
./scripts/install-machine.sh

# 5. Follow the interactive prompts:
#    - Enter target IP
#    - Select machine type (desktop/server)
#    - Confirm hostname (auto-generated)
#    - Choose disk from list
#    - Configure auto-updates
#    - Confirm installation
```

### What the TUI Provides

✨ **SSH Connection Test** - Verifies connectivity before starting  
🎯 **Smart Hostname** - Auto-suggests next hostname from your fleet  
💾 **Disk Discovery** - Shows physical disks with size & model  
🔄 **Auto-Updates** - Configure automatic flake updates  
⚠️ **Safety Checks** - Confirms before destructive operations

## Migration Checklist

### Before Migration
- [ ] Backup data from target machine
- [ ] Note the target machine's IP address

### During Migration  
- [ ] Boot NixOS USB on target
- [ ] Start SSH: `systemctl start sshd`
- [ ] Set password: `passwd`
- [ ] Run `./scripts/install-machine.sh` and follow TUI prompts
- [ ] Wait for completion (5-10 minutes)
- [ ] SSH into new system: `ssh root@<hostname>`

### After Migration
- [ ] Restore data from backup
- [ ] Test all hardware (graphics, audio, network)
- [ ] Update DNS/known_hosts (SSH key changed)
- [ ] Delete old pet config (optional)

## Troubleshooting

```bash
# Check what would be installed (dry run)
nix run github:nix-community/nixos-anywhere -- \
  --flake .#type-desktop \
  --target-host root@192.168.1.100 \
  --dry-run

# Debug disk detection
lsblk -f  # On target machine

# Test hardware detection
nix run github:nix-community/nixos-facter -- -o facter.json
```

## Next Steps

1. **Immediate**: Update SSH key in `flake.nix`
2. **Today**: Test VM install
3. **This week**: Migrate zero (gaming - test carefully)
5. **Later**: Evaluate flake-parts if desired

## Files Reference

| File | Purpose |
|------|---------|
| `flake.nix` | Added disko, nixos-facter inputs + configs |
| `scripts/install-machine.sh` | One-command installer |
| `machine-types/*.nix` | Generic system configs |
| `disk-configs/*.nix` | Disk layouts |
| `CATTLE.md` | Full documentation |
| `MIGRATION_SUMMARY.md` | Migration guide |

## Support

- [nixos-anywhere docs](https://github.com/nix-community/nixos-anywhere/tree/main/docs)
- [disko examples](https://github.com/nix-community/disko/tree/master/example)
- [nixos-facter](https://github.com/nix-community/nixos-facter)

Ready? Start with: `./scripts/install-machine.sh --help`
