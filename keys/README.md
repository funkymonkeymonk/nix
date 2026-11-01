# SSH Public Keys

This directory contains the single SSH public key authorized on managed NixOS systems.

`monkey-ssh.pub` is the public half of the `Homelab/monkey ssh` key in 1Password. The private half stays in 1Password and must never be committed. Nix configurations read the public key through `library/ssh-public-key.nix`; the installer also downloads this file for new systems.

When rotating the key, replace this file and update the corresponding public-key item in 1Password. Do not keep old keys alongside it.

## Rotating the Shared Key

1. Update `monkey-ssh.pub` with the approved public key.
2. Confirm its fingerprint matches the public-key field in 1Password.
3. Update the corresponding private-key field in 1Password; never commit a private key.
4. Commit and deploy the configuration change so systems stop authorizing the previous key.

## Security Notes

- Only add **public** keys (files ending in `.pub`)
- Never commit private keys
- Rotate keys periodically
- Keep only the approved public key in this directory
