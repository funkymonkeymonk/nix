---
title: "Use Zero and MegamanX as Nix Remote Builders"
description: "Configure and maintain reciprocal Nix builders with separate SSH identities"
type: how-to
audience: both
automation-ready: true
last-reviewed: 2026-11-14
---

# Use Zero and MegamanX as Nix Remote Builders

Zero and MegamanX can build for other Nix systems. Each long-lived system has its own SSH client identity. Builder hosts accept those identities only on a restricted `nixbuilder` account.

## Builder platforms

| Builder | Nix system | Host name |
|---|---|---|
| Zero | `x86_64-linux` | `zero` |
| MegamanX | `aarch64-darwin` | `megamanx` |

Clients can use either builder for derivations that match its system. The fleet's `type-server-arm` system is `aarch64-linux`; it builds that platform locally. Neither configured builder provides native `aarch64-linux` builds.

The host names must resolve and be reachable over the local network or Tailscale. Each client uses pinned public host keys. Do not replace a pin with an unverified `ssh-keyscan` result.

## Key separation

The public-only registry is `library/ssh-key-registry.nix`.

- `monkey-ssh.pub` is the human login key. It also remains the Git and Jujutsu signing key.
- Each Nix system has a distinct builder-client key. Zero reuses its existing Zero-to-MegamanX key. The other client keys are separate Ed25519 SSH Key items in the Opnix vault.
- `keys/hosts/zero.pub` and `keys/hosts/megamanx.pub` are public SSH host keys. Their private halves stay on their respective hosts.
- The Ultra Media service key remains separate from user and builder identities.

The registry authorizes each client key on both builder hosts, except a builder's own key on itself. Do not add builder keys to human login accounts.

## Runtime secret files

Nix needs a local, unencrypted private-key file for unattended remote builds. The Nix configuration stores only the file path, not the key value.

| Client OS | Private key file |
|---|---|
| NixOS | `/run/secrets/nix-builder-client` |
| Darwin | `/var/run/nix-builder-client` |

Opnix fetches the machine's key from its configured default vault and writes a root-owned mode `0400` file. SecretSpec provisions the Opnix service-account token at `/etc/opnix/token` with root-only permissions. The token is vault-scoped, so a host may be able to retrieve other builder-key items in the Opnix vault. Keep the token on trusted systems only.

On Darwin, `os/darwin.nix` sets `nix.enable = false` because Determinate Nix manages the Nix installation. Keep that setting. The flake writes builder records to `/etc/nix/machines` and builder settings to `/etc/nix/nix.custom.conf`; it does not ask nix-darwin to manage the Nix daemon.

## Add or rotate a client identity

1. Create or replace the client's Ed25519 SSH Key item in the `Opnix` vault.
2. Keep the private key in 1Password. Do not put it in Git, Nix expressions, command logs, or the Nix store.
3. Add only the matching public key to `keys/` and update that client's entry in `library/ssh-key-registry.nix`.
4. Confirm the private-key reference is unqualified so Opnix uses the machine's default vault.
5. Run `devenv tasks run check:lint` and `devenv tasks run test:build-checks`.
6. Create and review Machines plans for both builders and each client that needs the new identity. Apply only the reviewed plans.

To rotate a builder host key, verify the new public key from the host's local console or another trusted record. Update the host public-key file and its base64 pin in the registry. Review that pin change before deployment.

## Verify a client

Check that the secret file exists and has mode `0400`. Do not print its contents.

```sh
stat -c '%a %U:%G %n' /run/secrets/nix-builder-client
```

On Darwin, use `/var/run/nix-builder-client` with the macOS `stat` command. Check that the NixOS builder configuration or Darwin `/etc/nix/machines` lists the reachable peer. A local build can still run when no remote builder is reachable.
