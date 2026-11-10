---
title: "Migrate Media-Manager App State to the Local Media Host"
description: "Safely back up and migrate Arr, Bazarr, and Mylar3 state while preserving source services and rollback."
type: how-to
audience: operator
last-reviewed: 2026-11-09
---

# Migrate Media-Manager App State to the Local Media Host

Use this runbook during a separately approved maintenance window to move the existing Radarr, Sonarr, Lidarr, Bazarr, and Mylar3 state to the local media host. Keep the source state and media available for rollback. This runbook does not itself authorize a deployment, service change, or data deletion. Stop at any gate that is not satisfied.

## Before you begin

- Obtain explicit authorization for this migration and its cutover. Complete a read-only preflight and privately record each source and destination application's exact installed version and a version-supported restore/upgrade path. Do not assume versions or compatibility.
- Confirm destination services, local library roots, permissions, storage, and restore procedures are ready. The existing local library copy is complete; the legacy organized-library sync has been removed. Keep the completed-download staging timer disabled until cutover validation.
- Keep all application backups and private migration notes encrypted or access-restricted and outside the repository and Git history. Do not record backup contents or locations, endpoints, API keys, hostnames, remote paths, tracker names, or media names in this runbook, Git, or reports.
- Populate the required individual fields in Drlight's default **Opnix** vault before deploying a generation that references them. Do not put secret values in notes, shell history, logs, chat, or Git.
- Ultra's [Tailscale application is beta](https://docs.ultra.cc/applications/tailscale). Prove its private route from Prowlarr's actual application environment before relying on it. Never expose Arr APIs publicly as a fallback.

**Stop if:** any installed version, compatibility result, backup method, root mapping, or private route is unknown or unsupported. Do not resolve an uncertainty by experimenting against the only source copy.

## Prepare runtime secrets in Opnix

Drlight's OpNix service can read its configured default **Opnix** vault, not **Homelab**. Use the existing `Ultra Media Sync Config` secure note in Opnix, and add these fields individually; do not store a JSON document in its `config` field:

| Field | Value expected |
|---|---|
| `host` | Ultra SSH host |
| `username` | SSH username for the staging key |
| `knownHosts` | Pinned SSH known-hosts entry or entries |
| `rpcUrl` | Full HTTPS Transmission RPC endpoint |
| `completedDownloadsRoot` | Absolute remote root containing completed payloads |

The SSH port defaults to `22` in Nix. The existing `Ultra Media Sync Key/private key` item is already in Opnix and needs no new field. The current `Ultra - Transmission` login is in Homelab, which the Opnix service cannot access. Keep the login item in Opnix with `username` and one unambiguous `password` field that the Drlight Opnix service account can resolve. Remove the duplicate custom password field if it causes ambiguous references. Do not add a Homelab-qualified reference to Nix. The local Arr apps import completed torrent payloads from staging into the library; no organized-library source mapping is used.

Do not deploy until the Opnix fields and Transmission login are available to the Opnix service. After the fielded configuration has been verified, the obsolete JSON `config` field can be removed from the secure note.

## 1. Back up each application's state

Create an application-native backup for every source app before restoring or reconfiguring its destination counterpart. Verify each backup is complete and readable, retain an untouched copy outside Git, and preserve source services and data throughout the rollback period.

1. **Radarr:** In **System → Backup**, create a built-in backup and download the completed archive. Verify it appears in the backup list. Use the deployed release's documented restore workflow; see the [official Radarr FAQ](https://wiki.servarr.com/radarr/faq) for backup and restore guidance.
2. **Sonarr:** In **System → Backup**, create and download a built-in backup, then verify the completed archive. Use the deployed release's documented restore workflow; see the [official Sonarr FAQ](https://wiki.servarr.com/sonarr/faq) for backup and restore guidance.
3. **Lidarr:** Create and verify a backup using the procedure for the installed release. Follow the [official Lidarr backup guidance](https://wiki.servarr.com/en/lidarr/tips-and-tricks) for backup and restore.
4. **Bazarr:** Use the deployed version's **System → Backups** section and follow the [official Bazarr Wiki](https://wiki.bazarr.media/) and its [official backup/restore implementation reference](https://github.com/morpheus65535/bazarr/commit/5bfaba9360f062965e672dd336fe82208c716d13). Wait for a completed backup and verify the artifact is readable. Do not copy a live database file as a substitute.
5. **Mylar3:** Use the deployed version's documented **Auto-Backups** feature to create and verify its database and configuration backups. Follow the [official Mylar3 Auto-Backups guide](https://github.com/mylar3/mylar3/wiki/Auto-backups); do not guess a command or use an undocumented backup method.
6. Privately record only each app's version, backup time, and verification result. Keep the untouched backup archives in the protected location.

**Stop if:** an installed version lacks the documented native backup workflow, any artifact is incomplete or unreadable, both Mylar3 database and configuration backups are not present, or Bazarr has not produced a completed backup through **System → Backups**.

## 2. Confirm restore compatibility before applying state

Compare source and destination versions against the official guidance linked above. Confirm the supported restore and upgrade sequence for the exact deployed versions before using an archive. Prefer each app's documented restore workflow and validate compatibility on an isolated, disposable instance before applying state to an active destination. Keep the pristine archive if a test restore changes it or upgrades its database.

- **Radarr, Sonarr, and Lidarr:** Restore only through the workflow documented for the installed release, and follow its instructions for version and library-root changes. Refer to the [Radarr FAQ](https://wiki.servarr.com/radarr/faq), [Sonarr FAQ](https://wiki.servarr.com/sonarr/faq), and [Lidarr backup guidance](https://wiki.servarr.com/en/lidarr/tips-and-tricks), respectively.
- **Bazarr:** Use the restore workflow documented for the deployed version, with the [Bazarr Wiki](https://wiki.bazarr.media/) and [official backup/restore implementation](https://github.com/morpheus65535/bazarr/commit/5bfaba9360f062965e672dd336fe82208c716d13) as references. Verify whether that version accepts a backup from another instance. If cross-instance restore is unsupported or not established, stop. Do not assume copying database/configuration files is safe; proceed only with an official, version-supported method verified on an isolated copy. See [official issue 2311](https://github.com/morpheus65535/bazarr/issues/2311) for restore limitations.
- **Mylar3:** Follow the restore method supported by the installed release and the [official Auto-Backups guide](https://github.com/mylar3/mylar3/wiki/Auto-backups). If the supported restore method is not documented or compatibility is uncertain, stop and obtain a verified path before touching the active destination.

**Stop if:** the destination would require an unsupported downgrade, an unverified upgrade, or an undocumented database conversion. A service starting successfully does not by itself prove restore compatibility.

## 3. Verify the existing local library; do not sync the organized seedbox library again

The local library bootstrap is complete. The legacy organized-library sync service and timer have been removed. The steady-state transfer is only from Transmission's completed-download root into local staging; the local Arr apps then import from staging into their library roots.

1. Confirm `/srv/media` is mounted and the existing local library is available to the destination Arr apps.
2. Compare aggregate local library counts against the already-recorded migration baseline and verify representative entries under the expected local roots. Keep only aggregate results in private notes.
3. Do not run a recursive organized-library rsync from Ultra or configure ongoing syncing of the seedbox's organized media tree. Do not enable completed-download staging until the private connections and Arr remote-path mappings are ready in later steps.

**Stop if:** the existing local library is missing or materially disagrees with the migration baseline. Do not repair it by reintroducing a recurring organized-library sync; investigate the discrepancy separately before Arr imports.

## 4. Restore state and remap library roots

Restore one app at a time using the version-approved workflows in Step 2. Keep downloads paused and do not begin Arr imports until Step 3 is complete.

1. Confirm the destination app is at the approved version and is not processing downloads. Restore its verified native archive using its documented workflow and the linked app-specific source in Steps 1–2.
2. Replace each old library root with its verified local counterpart. Apply each one-to-one root remap only after confirming the destination root exists. Do not record root values in notes or Git.
3. Run the app's supported library refresh/rescan. Verify monitored state, aggregate library totals, and representative records against the private source baseline. Confirm the app does not interpret an unavailable old root as a new empty library.
4. Repeat for Radarr, Sonarr, Lidarr, and Mylar3. Keep the source app state and pristine backups intact.

For Bazarr, use only its installed version's supported restore path. If a cross-instance restore is unsupported, stop as specified in Step 2; do not substitute a file-copy restore.

**Stop if:** any root mapping is ambiguous, expected records disappear, migration errors occur, or aggregate counts do not reconcile.

## 5. Configure and test private application connections

Use only approved runtime connection data. Do not place values in this runbook, shell history, logs, tickets, or Git.

1. **Transmission:** Configure each destination Arr app to use the existing authenticated Transmission RPC connection and run its built-in test. Do not expose RPC or Arr APIs publicly.
2. **Remote-path mappings:** In each applicable Arr app, map the actual Transmission-reported download location to `/srv/media/.arr-staging`. Verify the exact reported path and local stage root during the approved preflight; do not infer the source mapping from a library category. A mapping does not transfer data by itself.
3. **Prowlarr:** Keep Prowlarr on Ultra. Prove Ultra's beta Tailscale route from Prowlarr's application environment, then configure and test its Arr integrations over that private route. Do not open a public Arr API port, use a public proxy, or bypass Ultra for indexer requests.
4. **Bazarr:** Configure its Sonarr/Radarr integrations to use the local destination apps and their API authentication. Run its connection tests and verify synchronization completes.
5. Keep Prowlarr, FlareSolverr, and Transmission on Ultra. Do not uninstall or relocate them.

**Stop if:** a connection test fails, the private route cannot be proven, credentials are unavailable from the approved runtime source, or indexer requests would bypass Ultra.

## 6. Perform the approved cutover and validate destination apps

Obtain separate cutover approval. Keep downloads paused during the transition. Preserve all source state and backups.

1. Confirm Steps 1–5 passed and the existing local library is available. Confirm `myConfig.ultraMediaDownloadStage.enable` remains `false`; completed-download staging must stay disabled until runtime settings and cutover have been validated.
2. With downloads paused, stop the old Ultra Radarr, Sonarr, Lidarr, Mylar3, and Bazarr services. Keep their data and backups for rollback. Do not stop or uninstall Prowlarr, FlareSolverr, or Transmission.
3. Start the Drlight apps. Verify their service and database health, library refreshes and aggregate counts, Transmission integration, private Prowlarr connectivity/sync, and Bazarr connectivity/sync. Confirm no Arr API is publicly reachable and indexer traffic remains on Ultra.
4. If any check fails, stop and use **Roll back**. Do not start completed-download staging to work around a failure.

## 7. Validate staging before enabling its timer

Keep the staging timer disabled while validating runtime settings and cutover health. The oneshot staging service can be tested deliberately while its recurring timer remains disabled.

1. Confirm approved runtime configuration contains the required connection data and every applicable remote-path mapping is exact. Confirm the staging service selects only completed downloads, uses the established copy-only transfer, and writes to the dedicated local staging area outside library roots.
2. Run an approved one-shot staging test for a controlled completed item. Check success and aggregate transfer results; verify the local staged item matches the normal size-and-modification-time comparison.
3. Let the relevant Drlight Arr app import from local staging into its verified library root. Verify the local file and app record exist and that no source data was moved or deleted. Repeat for each applicable category. Do not record item names or locations.
4. Only after runtime mappings, app health, and these staging/import checks pass, separately enable the recurring completed-download timer through the approved Nix configuration. Keep cleanup disabled/report-only.

**Stop if:** a transfer or import fails, a staged item is partial or mismatched, an Arr mapping does not resolve, source data is touched, or the local app cannot prove the imported file exists. Leave the recurring staging timer disabled.

## Roll back

If validation fails, keep downloads paused and perform these steps in order:

1. Stop Drlight Arr imports and destination staging. Through the approved Nix configuration, keep or set `myConfig.ultraMediaDownloadStage.enable = false;` so its recurring timer remains disabled. Wait for any staging oneshot to become inactive and confirm no Arr import is in progress.
2. Keep the legacy organized-library sync removed. The existing local library remains in place; rollback restores the preserved Ultra apps and their prior state without syncing the organized library back into Drlight.
3. Restart the preserved Ultra Arr/Bazarr services from their original state. Restore their prior Prowlarr integration configuration from the approved runtime source as needed; keep Prowlarr, FlareSolverr, and Transmission on Ultra.
4. Verify source apps can read their original state and library. Keep destination state, all backups, and source data until the incident is understood and another cutover is approved.

Do not remove torrents, staged data, library data, source app data, Prowlarr, FlareSolverr, or Transmission as part of rollback.

## Review legacy copies without deleting anything

After migration validation, perform a separate report-only review of legacy organized-library copies and torrent-owned payloads. Report aggregate counts only; do not delete or move files, remove torrents, or infer that successful migration makes old copies redundant. Any cleanup requires separate review and explicit approval after ownership is proven.
