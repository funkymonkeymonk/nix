# Ultra.cc to Drlight Direct Media Sync Implementation Plan

> **Retired:** This historical plan describes the organized-library sync, which has been removed now that Drlight's local library is complete. Current steady state stages completed Transmission torrents for local Arr import; see [the expanded media-retention plan](2026-11-09-ultra-media-retention.md). Do not use this plan to configure a sync service.
>
> **Note:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Set up a recurring, safe rsync pull of Ultra.cc's organized media library into Drlight's ZFS-backed Jellyfin library.

**Architecture:** A Drlight-only NixOS module provides an hourly systemd oneshot and timer. The service runs as a dedicated unprivileged user and pulls configured remote folders directly into local `/srv/media` roots. One 1Password JSON configuration supplies all endpoint, account, port, remote path, category, and host-key data; the private key is a separate 1Password secret. Ultra.cc remains the source of truth and retains its files; Jellyfin continues to scan its UI-managed libraries.

**Tech Stack:** NixOS modules, systemd service/timer, rsync over OpenSSH, OpNix/1Password, Nix evaluation checks, Jujutsu.

---

## Task 1: Add failing configuration tests (RED)

**Files:**
- Modify: `tests/test-media-center-archetype.nix` in `checks.drlightMediaStorageTest`

Add assertions for expected behavior before adding the module:

- Drlight selects a dedicated Ultra media-sync module.
- `ultra-media-sync.service` is a oneshot that runs as a dedicated unprivileged account, is ordered after network and ZFS mounting, requires `/srv/media` to be a mountpoint, and waits for OpNix secrets.
- The service command reads runtime JSON connection data and a runtime private-key file. It builds the rsync source endpoint from that data; endpoint/account/remote-path/category/host-key values must not be literal command strings or Nix values.
- The command includes the documented bandwidth cap, hidden partial-transfer handling, delayed updates, and strict SSH host-key checking. It does not include `--delete`, `--remove-source-files`, or seedbox owner/permission preservation. Add a local rsync behavior test proving restrictive source modes normalize to readable/traversable 0664/0775 destinations without other-write.
- The hourly persistent timer activates the service.
- OpNix materializes the config and key with ownership/permissions restricted to the service account and uses an unqualified item reference resolved through Drlight's `Homelab` default vault.
- `/srv/media/comics` is prepared, and `/srv/local/cache/ultra` is no longer created for this transfer.

Use existing `checkTrue`, `checkFalse`, and `checkEqual` helpers. Assert evaluated service/timer and secret configuration where possible. Do not add real seedbox values to the tests, including host, account name, paths, categories, or host key.

**RED verification:**

Run from the workspace root:

```bash
nix build .#checks.x86_64-linux.drlight-media-storage --no-link --impure
```

Expected: the check fails because the sync service/timer/module and comics root are not configured yet.

## Task 2: Implement the Drlight-only sync module

**Files:**
- Create: `modules/nixos/ultra-media-sync.nix`
- Modify: `library/machines/catalog.nix` in the `drlight.modules` list
- Modify: `modules/nixos/media-config.nix` in `mediaLibraryPaths`
- Modify: `modules/nixos/media-storage.nix` to remove the obsolete NVMe seedbox staging directory
- Modify: `tests/test-media-center-archetype.nix` to align the OpNix unit name and synthetic known-hosts fixture with existing NixOS patterns and the approved secret schema
- Modify: `tests/test-coverage.nix` to register the newly covered module

Implement a module that:

1. Declares `ultra-sync` as a system user in the existing `users` group. Give the service only the library access needed; do not run the transfer as root.
2. Registers two OpNix runtime files using unqualified references resolved through the `Homelab` default vault:
   - a JSON connection config at `/run/secrets/ultra-media-sync-config.json`, mode `0400`, owner `ultra-sync`, group `users`;
   - the private key at `/run/secrets/ultra-media-sync-key`, mode `0400`, owner `ultra-sync`, group `users`.
3. The JSON config contains the seedbox host, username, SSH port, remote media root, configured source subpaths with their local destination mapping, and pinned SSH known-hosts data. No such values may be embedded in source code, tests, documentation, or Git. Local destination roots and the bandwidth cap may remain in Nix.
4. Uses `jq` to read the runtime config and constructs one rsync invocation per configured source mapping. Materialize the NUL-delimited mapping stream to a temporary file with a checked jq producer before reading it, so malformed NUL mappings fail the service. Pull directly into configured local roots under `/srv/media`. Use `--protect-args` (or an equivalent safely quoted remote-path mechanism) so source paths containing spaces work. Apply `--perms` only with the fixed local normalization policy `--chmod=Du=rwx,Dg=rwx,Do=rx,Fu=rw,Fg=rw,Fo=r,ugo-s,o-t` (directories 0775, files 0664; set-ID and sticky bits cleared; no other-write), rather than retaining seedbox modes. Use a 20,000 KiB/s cap, hidden partial directory, delayed updates, itemized journal output, batch SSH, and strict host-key checking. Before any SSH call, use `ssh-keygen -F` with the runtime host alias (plain host for port 22, `[host]:port` otherwise). Enumerate remote folders as NUL-delimited basenames. Do not use `--delete`, `--remove-source-files`, numeric IDs, or seedbox ownership preservation.
5. Does not follow symlinks; preserves recursive directory layout and regular-file modification times while deliberately omitting directory timestamps. Set a group-friendly umask so created library files remain accessible to Jellyfin.
6. Defines `ultra-media-sync.service` as a oneshot ordered after `network-online.target` and `zfs-mount.service`, with `ConditionPathIsMountPoint = "/srv/media"`, and dependencies on the OpNix secret service. Set `restartIfChanged = false` so a running transfer does not block a NixOS switch; later runs use the updated unit. Failures leave source files untouched and retry on the next timer tick.
7. Defines an hourly `ultra-media-sync.timer` with `Persistent = false`, a small randomized delay, and `WantedBy = ["timers.target"]`. Missed ticks wait until the next hourly slot rather than launching a catch-up transfer during system activation.
8. Adds the local `comics` root to `media-library-folders.service`; leave Jellyfin's UI-managed library configuration and the other existing roots unchanged.

Keep the existing `/srv/local/state` tmpfiles rule. Remove only the obsolete `/srv/local/cache/ultra` seedbox staging rule. Do not add a Jellyfin API password or separate *arr services to Drlight.

**GREEN verification:** rerun the focused check from Task 1 and confirm it passes.

## Task 3: Provision and authorize the dedicated SSH identity

**Files:**
- Do not add the dedicated public or private key to Git.
- External: the Ultra.cc account's `~/.ssh/authorized_keys`
- External: the `Homelab` 1Password vault

Steps:

1. Create the dedicated Ed25519 keypair directly in a 1Password SSH Key item using the CLI's SSH-key generation feature. Do not generate or display a private key in a local file.
2. Create two purpose-typed 1Password items in `Homelab`: a Secure Note containing the JSON connection config, and an SSH Key item containing the generated private key. The JSON values include the endpoint, account, port, remote paths/category mapping, and pinned known-hosts data. Use unqualified item/field references in Nix. Verify the OpNix references and confirm Drlight's existing service-account token can read both items in `Homelab`.
3. Use the SSH host key already accepted during the authorized inspection to populate the 1Password known-hosts field. Keep strict host-key checking enabled; do not trust changed keys silently.
4. Append the existing personal public key from `keys/monkey-ssh.pub` to Ultra.cc `~/.ssh/authorized_keys`, preserving existing entries and avoiding duplicates.
5. Append the dedicated public key with `restrict` options so the job cannot request forwarding or an interactive TTY while rsync remote execution continues to work. Preserve existing entries and avoid duplicates. Do not change Ultra.cc's configured shell or install software there.
6. Verify the private key and connection config values are absent from Git, key fingerprints match, and the scheduled service does not use password authentication.

The user explicitly authorized adding both public keys to the seedbox. Do not deploy or switch Drlight from this task.

## Task 4: Complete regressions and validation

**Files:**
- Modify: `tests/test-media-center-archetype.nix` only as needed to align existing storage assertions with removal of NVMe staging and addition of the comics root

Run:

```bash
nix build .#checks.x86_64-linux.drlight-media-storage --no-link --impure
devenv tasks run check:lint
devenv tasks run test:build-checks
devenv tasks run test:eval
```

Expected: all commands pass. Inspect `jj diff` and verify no private key or seedbox connection/configuration values were written into the repository. Confirm the Drlight timer is configured but do not deploy until the whole-branch review is clean. The initial transfer may be large; the rate cap and no-delete behavior remain in force.

## Task 5: Deploy Drlight and start the first sync

**Files:**
- No tracked source changes; use the approved NixOS deployment workflow for the existing `drlight` target.

The user explicitly requested that the sync process start promptly. After Tasks 1–4 validation and the whole-branch review:

1. Run the repository deployment task from this Jujutsu workspace: `devenv tasks run machines:deploy --input machine=drlight --input yes=true`. Stop if it requires an interactive Op approval or otherwise fails; do not use insecure credential fallbacks.
2. Verify the NixOS switch enabled `ultra-media-sync.timer`, OpNix materialized both secret files with expected service ownership/modes, `/srv/media` is mounted, and the service can read runtime config without printing values.
3. Start one immediate run without waiting for the hourly timer: `sudo systemctl start --no-block ultra-media-sync.service` on Drlight. Verify the service is active and its journal shows normal rsync activity; do not expose connection details or media filenames in the report.
4. Keep the transfer copy-only. Do not delete any additional Ultra.cc media or torrent data; source cleanup remains a manual, separately confirmed operation.

The initial sync may be large and can continue in the background while the user is away. The service's configured rate cap and mount guard remain in force.

## Commit checkpoints

Use Jujutsu in the dedicated workspace. Keep the design and implementation history local; do not push. Deploy only in Task 5, after validation and whole-branch review, as explicitly requested by the user. After each completed task, describe the working copy with a conventional message and start a fresh child commit. The working copy is the commit, so no Git staging is needed for tracked files; use `jj file track` for any new files before Nix evaluation.
