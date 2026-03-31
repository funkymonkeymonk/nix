# SSH Public Keys

This directory contains SSH public keys for authorized access to NixOS systems.

## Naming Convention

Keys should be named: `username@hostname.pub`

Examples:
- `monkey@MegamanX.pub`
- `wweaver@workstation.pub`

## Usage

These keys are used by the `scripts/nixos-install.sh` installer to set up SSH access on new systems.

## Adding a New Key

1. Copy your public key to this directory:
   ```bash
   cp ~/.ssh/id_ed25519.pub keys/username@hostname.pub
   ```

2. Commit and push:
   ```bash
   git add keys/
   git commit -m "feat: add SSH key for username@hostname"
   git push
   ```

## Security Notes

- Only add **public** keys (files ending in `.pub`)
- Never commit private keys
- Rotate keys periodically
- Remove keys for systems that are no longer in use
