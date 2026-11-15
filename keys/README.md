# SSH Public Keys

This directory contains public SSH keys only. Private keys stay in 1Password or on their host.

| File | Purpose | Private-key location |
|---|---|---|
| `monkey-ssh.pub` | Human SSH login and Git/Jujutsu signing identity | `Homelab/monkey ssh` in 1Password |
| `nix-remote-builder-megamanx.pub` | Zero's builder-client identity, accepted by MegamanX and other builders | `Opnix/Nix Remote Builder Zero to MegamanX` in 1Password |
| `nix-builder-client-<machine>.pub` | One Nix builder-client identity per other managed machine | Matching `Opnix/Nix Builder Client <machine>` SSH Key item |
| `hosts/zero.pub` | Zero's SSH host identity pin | Generated and kept on Zero |
| `hosts/megamanx.pub` | MegamanX's SSH host identity pin | Generated and kept on MegamanX |

`library/ssh-public-key.nix` provides the human login key to system archetypes. `library/ssh-key-registry.nix` maps builder-client identities and pinned builder host keys to their roles. Do not use every `.pub` file as a login key.

## Rotate a Human Login Key

1. Replace `monkey-ssh.pub` with the approved public key.
2. Confirm its fingerprint matches the public-key field in 1Password.
3. Update the matching private-key item in 1Password. Never commit a private key.
4. Run the SSH authorization tests and review the machine deployment plan.
5. Apply the reviewed configuration so hosts stop authorizing the previous key.

## Rotate a Builder-Client Key

1. Create an Ed25519 SSH Key item in the machine's `Opnix` default vault.
2. Replace only the matching public `.pub` file and registry reference.
3. Confirm that the registry adds the key to both builder hosts and not to the client's own builder account.
4. Run `devenv tasks run check:lint` and `devenv tasks run test:build-checks`.
5. Review and apply plans for the client and both builders.

## Rotate a Builder Host Key

Verify the host's new public key from its local console or another trusted record. Update `hosts/<machine>.pub` and the matching base64 host-key pin in `library/ssh-key-registry.nix`. Do not trust an unverified `ssh-keyscan` result.

## Security Notes

- Commit public keys only. Never commit private keys or Opnix tokens.
- Keep the human login key, builder-client keys, and host keys separate by role.
- Builder private-key files are materialized by Opnix with root-only permissions.
- The Opnix service-account token can read items allowed by its vault permissions. Keep it on trusted systems only.
