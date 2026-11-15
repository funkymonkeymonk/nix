# SSH Builder Registry Design

**Status:** Approved by the user on 2026-11-14.

## Intent

Make Zero and MegamanX reciprocal Nix remote builders and make the other long-lived Nix systems able to use them when a derivation matches a builder's platform. Keep SSH identities explicit by purpose and keep private keys in 1Password, outside the Nix store.

## Scope

The long-lived catalog systems are `zero`, `drlight`, `type-nas`, `type-server`, `type-server-arm`, `type-desktop`, `Lydia`, `MegamanX`, and `wweaver`. `bootstrap` and `installer-iso` are excluded. Zero provides `x86_64-linux`; MegamanX provides `aarch64-darwin`. The existing `aarch64-linux` system (`type-server-arm`) remains a native builder for its own platform; the two configured remote builders do not provide `aarch64-linux` unless Zero is separately configured for emulation.

## Key model

Create one unique Ed25519 Nix-builder client key pair per long-lived system (nine pairs total). Each system uses its own private identity to authenticate to every other builder. Zero and MegamanX each authorize the other eight systems' public keys on a dedicated `nixbuilder` account; neither authorizes its own client key. The account remains trusted by the local Nix daemon and restricted to the Nix daemon SSH protocol, with no interactive shell, agent forwarding, port forwarding, TTY, or X11 forwarding.

A named public-only registry maps client system names to their public keys and maps builder names to platform, endpoint, and pinned host public key. Existing `monkey-ssh.pub` remains the user-login key and the current Git/Jujutsu signing key. The Ultra Media service key remains independent.

Darwin machines use Determinate Nix, and `os/darwin.nix` deliberately sets `nix.enable = false`. Do not enable nix-darwin Nix management. For Darwin clients and builders, write the machine list to `/etc/nix/machines` and builder settings to `/etc/nix/nix.custom.conf`. For NixOS, use `nix.buildMachines` and `nix.distributedBuilds`.

## Secret and host-key lifecycle

Store each private builder key in an unqualified 1Password reference resolved through the machine's configured default vault. Opnix materializes only that machine's configured client key to a root-owned mode `0400` local file; `nix.buildMachines.*.sshKey` remains a string path to that file, never a Nix path or Nix-store value. SecretSpec supplies the Opnix service-account token at provisioning time. The shared Opnix token's vault-level permissions may allow a host to retrieve more than its own key; this is an accepted operational tradeoff for this design and must be documented.

Import the pinned Opnix nix-darwin system module through the canonical system builders and enable the system secret service for participating systems. NixOS has the module available but its system service is disabled by default, so enablement and token provisioning must be explicit. Host private keys remain generated and persisted on each host. Public host-key pins are separate registry data; Zero's pin must be independently verified from a trusted existing record or local console before it is added. Never trust an unverified `ssh-keyscan` result.

## Network and builder selection

Use the canonical hostnames `zero` and `megamanx`; clients must be able to resolve and reach them over the local network or Tailscale. Configure each client to use the other applicable builder, never itself. Configure `distributedBuilds` and builder substitutes on clients. Host-key checking remains pinned.

## Non-goals

- No changes to machine deployment endpoints, system switch/deploy operations, or live hosts.
- No changes to the human login/signing key or Ultra Media key.
- No aarch64-linux emulation or third builder.
- No private key or resolved 1Password value in Git, Nix expressions, logs, or the Nix store.
- No automatic use of every `.pub` file as an authorized login key.

## Validation

Tests must prove the nine client identities are distinct and present; each builder authorizes exactly the other clients; each client configures compatible peers but never itself; both builders enforce the restricted account policy; secret references, runtime path type, owner and mode are correct; host-key pins match their public-key source; and no private key value enters the repository. The legacy local installer must not grant builder keys to its admin or guest accounts.
