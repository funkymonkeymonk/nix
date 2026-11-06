# Ultra.cc to Drlight Media Sync Design

**Status:** Approved; credential handling updated per user request  
**Date:** 2026-11-04

## Goal

Keep Drlight's Jellyfin library in sync with the organized media library on the Ultra.cc seedbox. Transfer files from Ultra.cc directly into Drlight's ZFS-backed `/srv/media` library. Do not stage the full transfer on the 2 TB NVMe cache.

A direct transfer avoids writing every file twice locally and does not constrain the source size to the NVMe cache capacity. The first run may transfer the existing library; subsequent runs should transfer only new or changed files. Connection details and remote paths are not stored in this repository.

## Responsibilities

- **Ultra.cc:** Keep Transmission, Radarr, Sonarr, Lidarr, and Bazarr in place. They already download, organize, and manage the remote media library.
- **Drlight:** Pull the organized files, keep the local library directories, and use Jellyfin's existing library scan and metadata providers. Do not duplicate the *arr applications on Drlight.

The seedbox remains the source of truth. The sync must not delete or modify source files.

## Transfer and scheduling

Add a Drlight-only NixOS module for a systemd oneshot sync service and hourly timer. Keep the hourly schedule and small randomized delay, but disable persistent catch-up so a missed tick waits for the next hourly slot instead of launching a long transfer during system activation. Set `restartIfChanged = false` so a running transfer can finish with its current unit definition; later runs use the updated unit. Systemd will serialize runs; a new run must not overlap an active transfer.

The service will use rsync over SSH. A runtime JSON configuration from 1Password supplies the remote hostname, username, port, media root, and source subpaths. Local destination roots and the bandwidth cap remain in Nix. Follow Ultra.cc's documented bandwidth guidance with a default cap of 20 MB/s. Do not enable rsync `--delete` or `--remove-source-files`.

Rsync should preserve directory structure and regular-file modification times while deliberately omitting directory timestamps, but must not preserve the seedbox's numeric owner/group IDs or restrictive permissions on Drlight. Apply a fixed local permission policy with `--perms --chmod=Du=rwx,Dg=rwx,Do=rx,Fu=rw,Fg=rw,Fo=r,ugo-s,o-t`: destination directories become 0775 and files 0664, with set-ID and sticky bits cleared, keeping write access for `ultra-sync`'s group while allowing Jellyfin's separate account to traverse/read without granting other-write. Do not follow or copy symlinks unless later inspection shows the source library requires them. Use a hidden partial-transfer directory and delayed updates so incomplete transfers are not published as final library files. Log itemized transfer results to the system journal. Existing same-path files follow rsync's normal size-and-modification-time comparison; destination-only files are retained because deletion is disabled. A failed run leaves source data untouched and remains safe to retry.

The service must wait for network availability and ZFS mounting, and must have `ConditionPathIsMountPoint=/srv/media` so it cannot accidentally write into the unmounted mountpoint directory. It should run as a dedicated unprivileged `ultra-sync` account in the existing `users` group, with write access to the library roots.

## Source-to-library mapping

The existing local roots `/srv/media/movies`, `/srv/media/shows`, and `/srv/media/music` are retained, and `/srv/media/comics` is added. The source subpaths and their corresponding local destinations are provided by the 1Password runtime configuration; source directory names and paths are not embedded in Nix, tests, or documentation. Only configured source entries are copied. Unknown remote categories should be reported in the journal for later review. No new media content is copied into `/srv/local/cache/ultra`.

## SSH identity and secrets

Add the existing personal public key in `keys/monkey-ssh.pub` to the seedbox account's `~/.ssh/authorized_keys` without removing existing entries. Create a separate Ed25519 key for the Drlight sync service. Store its private key and a JSON connection configuration in the machine's default 1Password vault (`Homelab`), not in Git or the Nix store. The JSON configuration contains the hostname, username, SSH port, remote media root, source subpaths and their local destination mapping, and pinned SSH host-key data. Use the existing OpNix integration to materialize the private key and JSON configuration at runtime with ownership and permissions restricted to `ultra-sync`. Add only the service key's public half to the seedbox, with SSH restrictions that disable forwarding and interactive features while still permitting rsync's remote command. Do not store endpoint, account, path, or host-key values in Nix source, tests, or documentation.

Use SSH public-key authentication for the scheduled job; do not put the seedbox password in Nix or use password-based automation. Before any SSH call, validate the configured known-hosts entry with `ssh-keygen -F`, using the plain hostname for port 22 and `[host]:port` for any non-default port; enforce strict checking rather than silently accepting a changed key. Materialize the jq NUL-delimited mapping stream to a temporary file with a checked producer command before reading it, so malformed mappings fail the service.

## Jellyfin and metadata

Ultra.cc's existing media applications remain responsible for organization and their metadata. Drlight's existing Jellyfin instance scans the destination library and retrieves its own metadata. The sync job should not need a Jellyfin admin password or change Jellyfin's UI-managed library configuration. Jellyfin's filesystem monitoring/scheduled library scan handles newly published files; no API credential is added.

## Failure and safety behavior

- Keep the seedbox library untouched, including on failure.
- Never enable destination deletion as a mirror policy.
- Retain partial transfers in a hidden rsync partial directory; retry on the next timer run.
- If `/srv/media` is not a mountpoint, do not run.
- Do not copy unknown source categories automatically; report them in the journal. Existing same-path files follow the documented rsync comparison policy; destination-only files are not removed.
- If the ZFS pool runs out of space, fail visibly in the service journal and retry only after space is available. The service must not clean up unrelated files to make room.

## Validation

Add an automated Nix evaluation/build check that verifies the Drlight-only service and timer, their schedule and network/ZFS dependencies, the dedicated account and secret permissions, runtime loading of remote configuration from OpNix, destination root creation, and the absence of embedded endpoint/path data, destructive rsync flags, or NVMe staging use. Run `devenv tasks run check:lint` and `devenv tasks run test:build-checks`; because Drlight target configuration is involved, also run the repository's NixOS evaluation check when available.

## References

- [Ultra.cc rsync guide](https://docs.ultra.cc/unofficial-ssh-utilities/rsync)
- [Ultra.cc download guide](https://docs.ultra.cc/misc-guides/download-from-your-ultra-service)
- [Ultra.cc SSH guide](https://docs.ultra.cc/connection-details/ssh/connect-to-your-ultra-slot-via-ssh)
