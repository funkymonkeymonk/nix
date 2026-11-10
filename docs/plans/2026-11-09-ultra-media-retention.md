# Drlight Media-Manager Migration and Ultra.cc Retention Implementation Plan

> **Note:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make Drlight the authoritative local media library and run its media-management apps locally, while retaining Ultra.cc as the torrent/indexer host and reclaiming seedbox space only after safe local import and seeding-policy checks.

**Architecture:** Drlight runs Radarr, Sonarr, Lidarr, Mylar3, and Bazarr against its ZFS-backed `/srv/media`. Ultra.cc keeps Transmission, Prowlarr, and FlareSolverr; Ultra's Tailscale beta provides a private path for Prowlarr app sync to Drlight. Drlight uses the existing pinned-SSH/rsync pattern to stage completed Transmission payloads locally, and Arr remote-path mappings point at those staged files. App state is backed up and migrated, paths are rewritten to Drlight, and old seedbox applications/data remain available for rollback until cutover is validated. Seedbox deletion remains fail-closed and report-only by default.

**Tech Stack:** NixOS service modules, Tailscale, OpNix, Python standard library, Transmission RPC, rsync over strict-host-key-checked SSH, Nix evaluation/build tests, Jujutsu.

---

## Binding policy and safety requirements

- Retain a complete torrent until it has at least **240 actual seeding hours OR a per-torrent upload/download ratio of 3.0**, whichever occurs first.
- For every associated private tracker, require the current account-wide ratio to be **at least 0.6**. Unknown trackers or unavailable ratio sources fail closed. The current configured Prowlarr indexers are public; do not invent private-tracker ratio APIs.
- A seedbox torrent is never eligible for removal until rsync successfully stages its complete payload and Drlight's Arr state confirms the imported local library file exists and matches by size and modification time. Do not add checksum scans.
- Do not add `--delete` or `--remove-source-files` to the rsync transfer. Do not directly `rm` seedbox data. Any torrent removal with local data must go through Transmission's documented RPC, using the deployed version's verified API.
- Report-only is the default. No install/switch, external Ultra app changes, or seedbox deletion is part of code validation.

## Task 1: Read-only migration and connectivity preflight

**Files:**
- Create: `/tmp` or another non-repository report only; do not store live endpoint/path details in Git.

**Step 1: Inventory application and package compatibility without changing either host**

Using read-only UCP/API/SSH access, determine:

- deployed versions and current state/back-up methods for Radarr, Sonarr, Lidarr, Mylar3, Bazarr, Transmission, Prowlarr, and FlareSolverr;
- Transmission's actual RPC schema/version, torrent-completion fields, download paths, and whether the prior read-only RPC adapter reaches the deployed endpoint;
- the existing organized-library paths, torrent payload paths, and any hardlink/shared-inode relationships, but report only counts/yes-no/compatibility results, never names or paths;
- whether Ultra's Tailscale beta can reach Drlight's Tailscale node from the Prowlarr app network namespace and call a test Arr API without opening any public Arr port;
- whether the pinned SSH identity can read the completed download data needed for rsync staging;
- whether the active nixpkgs revision provides NixOS services/packages for Radarr, Sonarr, Lidarr, and Bazarr, and whether Mylar3 needs a small local package/service module.

Do not change app configuration, install/enable Ultra Tailscale, export app databases, print secrets or identifiers, or call any removal API during discovery. If the Ultra Tailscale beta cannot connect from Prowlarr's network namespace, stop and revise the connectivity approach; do not expose Arr APIs publicly as a fallback.

**Step 2: Record the preflight report outside Git**

Record versions, supported API fields, aggregate torrent/media counts, connectivity pass/fail, mount/rsync feasibility, and backup compatibility. Do not record actual hostnames, media names, remote paths, passkeys, or credential values.

## Task 2: Preserve and test the retention policy and read-only RPC adapter

**Files:**
- Existing: `modules/nixos/scripts/ultra-media-cleanup.py`
- Existing: `modules/nixos/scripts/transmission_rpc.py`
- Modify: `tests/test-ultra-media-cleanup.py`
- Modify: `tests/test-ultra-media-cleanup.nix`

The current branch already has a pure retention evaluator and a read-only Transmission RPC adapter. Review and test those first; do not duplicate the evaluator. The controller's normalized candidate shape is `{complete, seeding_seconds, torrent_ratio, trackers, files}` and `evaluate_retention(candidate)` returns `{eligible, reasons}`.

**Step 1: Add failing adapter tests for the deployed read contract**

Use a local fake HTTP RPC server to cover session negotiation, torrent ID/completion/seeding-time/ratio fields, tracker hosts, download path/file list, API error handling, and current RPC version normalization. Assert read-only operations never issue `torrent_remove`.

**Step 2: Confirm RED**

Run:

```bash
nix build .#checks.x86_64-linux.drlight-ultra-media-cleanup --no-link --impure
```

Expected: new adapter contract cases fail before implementation changes.

**Step 3: Implement only the read-only adapter improvements required by preflight**

Support only documented legacy/current fields appropriate to the deployed Transmission version. When `leftUntilDone` and `percentDone` are available, classify a payload as complete only when they prove zero bytes remaining and 100% complete; do not use `isFinished` as a download-completion flag because it describes a seeding-stop condition. Fall back to the documented status field only for versions without those completion facts. Keep no removal method in the read adapter. If live endpoint/version remains unavailable, leave the adapter marked unverified and keep destructive cleanup disabled.

**Step 4: Run the focused check and confirm GREEN; commit**

```bash
nix build .#checks.x86_64-linux.drlight-ultra-media-cleanup --no-link --impure
jj describe -m "feat: verify transmission read adapter contract"
jj new
```

## Task 3: Add failing tests for Drlight media-manager services

**Files:**
- Create: `modules/nixos/media-management.nix`
- Create: `modules/nixos/mylar3.nix` only if no supported nixpkgs module exists
- Modify: `library/machines/catalog.nix`
- Modify: `tests/test-media-center-archetype.nix`
- Modify: `tests/test-coverage.nix`

**Step 1: Write Nix evaluation tests before service definitions**

Assert Drlight owns Radarr, Sonarr, Lidarr, Mylar3, and Bazarr; the services use the existing local media roots; Bazarr points to Drlight-local Sonarr/Radarr; their system users can read/write the configured library and staging roots via a deliberate shared-group/permission policy; and their APIs are reachable only over the Tailscale interface. Assert no Arr/Bazarr service is added to other machines.

For Mylar3, use a nixpkgs-provided package/module if preflight confirms it. Otherwise add a minimal pinned package and systemd module with isolated state, an unprivileged user, a health check, and test coverage; do not add the Nixarr flake input or a container stack without a new design review.

**Step 2: Run the focused test and confirm RED**

Run:

```bash
nix build .#checks.x86_64-linux.drlight-media-management --no-link --impure
```

Expected: the new Drlight service assertions fail because the services are not yet configured.

**Step 3: Implement Drlight service configuration**

Add the services using existing NixOS options and project module patterns. Keep their state under stable local service directories, enable no public application ingress by default, and add only the local library roots needed by each app. Use runtime secret files/OpNix references for credentials and API keys; do not include app databases, passwords, endpoint values, or remote paths in Git.

**Step 4: Run the focused test and confirm GREEN; commit**

```bash
nix build .#checks.x86_64-linux.drlight-media-management --no-link --impure
jj describe -m "feat: add local media management services"
jj new
```

## Task 4: Confirm the private app boundary; defer live Prowlarr setup to cutover

**Files:**
- Existing coverage: `tests/test-media-center-archetype.nix`
- Modify only if Task 3's assertions do not cover the firewall contract.

Task 3 configures and tests Drlight's Arr API ports on `tailscale0` only, keeps them closed globally/on other interfaces, and omits public Caddy apps. That is the code-side boundary for Ultra's future Prowlarr sync. Do not add the Ultra Prowlarr service or its runtime API key to Drlight Nix; Prowlarr stays on Ultra.

**Step 1: Verify the existing focused test covers all boundary outcomes**

Run the media-management check and confirm it asserts the ports are allowed only on `tailscale0`, not globally, on other interfaces, or via Caddy. If those assertions pass, make no duplicate code change. If a required assertion is missing, add it test-first and verify RED before the smallest fix.

**Step 2: Keep external Prowlarr/Tailscale setup out of code validation**

Do not install Ultra's Tailscale beta or configure Prowlarr's Arr API entries in this task. Those are cutover actions in the deployment checklist, after the user authorizes the UCP operation. If the live private route fails, stop rather than exposing Arr APIs publicly. No live route can be claimed verified while 1Password/UCP access is unavailable.

**Step 3: Record outcome and proceed**

Use Task 3's reviewed Drlight firewall assertions as the code-side evidence. The live Prowlarr-to-Arr API connection remains a deployment precondition, not a repository build success claim.

## Task 5: Add failing tests for rsync download staging and remote-path mapping

**Files:**
- Create: `modules/nixos/ultra-media-download-stage.nix`
- Create: `modules/nixos/scripts/ultra-media-download-stage.py`
- Modify: `modules/nixos/scripts/ultra-media-cleanup.py`
- Modify: `modules/nixos/media-management.nix`
- Modify: `tests/test-media-center-archetype.nix`
- Modify: `tests/test-ultra-media-cleanup.py`
- Modify: `tests/test-ultra-media-cleanup.nix`
- Modify: `tests/test-coverage.nix` if the new staging module needs explicit coverage registration

**Step 1: Write staging tests before changing the transfer**

Test that only Transmission-complete torrent payloads are considered; incomplete/unknown files are skipped; whitespace/nested paths are safely handled; payloads map to the hidden `/srv/media/.arr-staging` directory on the same ZFS filesystem as the library; staging is excluded from Jellyfin/Arr library scans; failed/partial transfers are not reported as complete; and rsync uses neither `--delete` nor `--remove-source-files`. Test the normalized remote-to-staging mapping helper without writing to an Arr database. Test that the staging timer is disabled by default and the legacy organized-library sync service/timer are absent.

**Step 2: Confirm RED**

Run the focused Nix check and the Python tests. Expected: staging/schema/mapping tests fail because the staging service is absent.

**Step 3: Implement a separate completed-download staging service**

The organized-library bootstrap is complete and its legacy sync service/timer are removed. Add only `ultra-media-download-stage.service` and its timer, with an explicit enable option defaulting to false. The stage service queries complete Transmission torrents using the read-only adapter and rsyncs their payloads through the existing pinned SSH identity into the hidden non-library stage on the local ZFS filesystem. Drlight Arr apps then import from that local stage into their library roots. No seedbox data is deleted.

Use individual unqualified Opnix field references instead of a runtime JSON blob. The `Ultra Media Sync Config` secure note in Drlight's default `Opnix` vault supplies `host`, `username`, `knownHosts`, `rpcUrl`, and `completedDownloadsRoot`; the SSH port defaults to 22 in Nix. No `mediaRoot` or organized-library source mapping is required. Add unqualified references for `Ultra - Transmission/username` and the service-account-resolvable `Ultra - Transmission/password`, scoped to the stage service. If a required field or credential is absent/malformed, emit a safe reason and do not transfer. Do not modify 1Password in this task. Before deployment, the user must populate the listed fields in `Opnix` and move/copy the existing Transmission login item from `Homelab` into `Opnix`; the service cannot read `Homelab`.

Keep logs to aggregate counts and safe reason codes; never print torrent names, filenames, remote paths, API URLs, or credentials. Remote path values remain in runtime secrets.

**Step 4: Define the mapping contract for Task 6 cutover**

Expose/test the normalized Transmission remote path to local staging path mapping. Do not mutate Arr databases or call Arr APIs in this task: the actual remote-path mapping and download-client settings are applied during Task 6 app-state restore/cutover. The cutover mapping must point to the exact staged representation and imports must never move/delete Ultra source data. Keep Prowlarr indexer requests proxied through Ultra; do not enable `Redirect` for an indexer unless required and reviewed.

**Step 5: Run focused checks and commit**

Run the policy, RPC, staging, and Drlight evaluation checks; commit with `jj describe -m "feat: stage completed seedbox downloads locally"`.

## Task 6: Document app-state migration and torrent-staging cutover

**Files:**
- Modify: `modules/nixos/ultra-media-download-stage.nix`
- Modify: `tests/test-media-center-archetype.nix`
- Create: `docs/how-to/migrate-ultra-media-apps-to-drlight.md`

**Step 1: Write failing tests for the cutover timer controls**

Assert that the legacy organized-library sync service and timer are absent, and that the completed-download stage timer remains disabled by default until separately enabled. No API keys, remote paths, or external endpoint values belong in these tests.

**Step 2: Confirm RED; implement the persistent timer option**

Remove the legacy organized-library sync option, service, and timer entirely. Keep `myConfig.ultraMediaDownloadStage.enable` defaulted to `false` so only the torrent-staging timer is opt-in.

**Step 3: Write the migration how-to with official, version-appropriate references**

Create `docs/how-to/migrate-ultra-media-apps-to-drlight.md` as one goal-oriented how-to. Link the official Radarr backup/restore FAQ (`https://wiki.servarr.com/radarr/faq`), Sonarr FAQ (`https://wiki.servarr.com/sonarr/faq`), Lidarr backup guidance (`https://wiki.servarr.com/en/lidarr/tips-and-tricks`), Bazarr Wiki and backup/restore implementation/reference (`https://wiki.bazarr.media/`, `https://github.com/morpheus65535/bazarr/commit/5bfaba9360f062965e672dd336fe82208c716d13`), Mylar3 Auto-Backups guide (`https://github.com/mylar3/mylar3/wiki/Auto-backups`), and Ultra Tailscale beta documentation (`https://docs.ultra.cc/applications/tailscale`).

The runbook must require a read-only version/compatibility preflight, application-native backups stored outside Git, verification of the already-complete local library, and state restoration/root remapping on Drlight. It must state that the organized-library sync service/timer have been removed and are not part of steady state. At the approved cutover, restore/configure Drlight apps while downloads are paused, stop the old Ultra Arr/Bazarr services, start the Drlight apps, verify library/indexer/Transmission/Bazarr health, then enable completed-download staging. For rollback, stop Drlight imports and staging, then restart the preserved Ultra apps; do not reintroduce organized-library syncing. Do not uninstall Prowlarr, FlareSolverr, or Transmission.

For Bazarr cross-instance restore, follow the deployed version's documented backup workflow. If the built-in restore does not accept a backup from another instance, stop and use only an official/version-supported database/config restore method verified on an isolated copy; do not assume file-copy restore is safe. Never record app backups, endpoints, API keys, hostnames, remote paths, tracker names, or media names in the runbook.

**Step 4: Review the how-to and run the focused evaluation checks**

Confirm the doc serves only the How-to quadrant, every app backup/restore claim links to a primary source, no secret/live endpoint data appears, staging starts only after Arr setup, and the rollback path is explicit. Run the focused Drlight media-management/storage checks and repository lint; commit with a conventional `docs:` or `fix:` message matching the code changes.

Do not export app databases, alter 1Password, stop services, or perform any deployment/cutover in this plan-writing/code-validation task.

## Task 7: Gate cleanup on successful local Arr import and account policies

**Files:**
- Modify: `modules/nixos/scripts/ultra-media-cleanup.py`
- Modify: `modules/nixos/ultra-media-cleanup.nix`
- Modify: `modules/nixos/ultra-media-download-stage.nix`
- Modify: `modules/nixos/scripts/ultra-media-download-stage.py`
- Modify: `tests/test-ultra-media-cleanup.py`
- Modify: `tests/test-ultra-media-cleanup.nix`
- Modify: `tests/test-media-center-archetype.nix`

**Step 1: Add failing tests for the migration-aware cleanup gate**

Besides the existing 240-hour-OR-3.0, 0.6 private account floor, unknown-tracker fail-closed, and path-overlap cases, test that cleanup is blocked when rsync staging failed, the Arr app has not imported the payload, any mapped local library file is missing/mismatched by size+mtime, the app state cannot prove the import, or Tailscale/RPC status is unavailable. Test that cleanup only runs after a successful staging unit and import verification, that systemd serializes staging/cleanup, that report-only is the default, and that no failure path calls Transmission remove.

**Step 2: Confirm RED; implement the report-only cleanup controller**

Run candidate-specific rsync verification and query local Arr import state only through a documented/supported interface. Trigger cleanup only after the staging service succeeds, then recheck Transmission/torrent/tracker state immediately before a removal request. Unknown app imports, unknown private-tracker ratios, ambiguous legacy library paths, or shared torrent files block deletion. Keep destructive mode disabled in Drlight configuration.

**Step 3: Add the explicit Transmission removal gate only after deployed-version verification**

Use only the deployed Transmission RPC version's documented remove-with-local-data argument. If the endpoint/version cannot be verified in preflight, leave the removal operation unreachable and report-only; do not guess a field or fall back to direct filesystem deletion.

**Step 4: Run all focused checks and commit**

The focused tests must prove no remove request occurs for any failed import/verification/ratio/API condition and that report-only mode never removes files.

## Task 8: Inventory legacy Ultra library copies without deleting them

**Files:**
- Modify: `modules/nixos/scripts/ultra-media-cleanup.py` only if needed for an aggregate report mode
- Modify: `tests/test-ultra-media-cleanup.py`

Produce a read-only aggregate report distinguishing Transmission-owned payload data from old Arr-organized library paths, including whether they share inode/path ownership. Never delete legacy library entries as a side effect of the torrent cleanup service. If reclaiming those separate legacy copies is still needed after cutover, present a dry-run inventory for explicit user review and approval before a separate cleanup operation.

## Task 9: Validate without deploying

Run:

```bash
nix build .#checks.x86_64-linux.drlight-media-management --no-link --impure
nix build .#checks.x86_64-linux.drlight-ultra-media-cleanup --no-link --impure
devenv tasks run check:lint
devenv tasks run test:build-checks
devenv tasks run test:eval
```

Review `jj diff` for secrets, hostnames, account names, tracker domains, source paths, API keys, and default-enabled deletion. Do not deploy/switch Drlight, install Ultra's Tailscale beta, stop/uninstall Ultra apps, edit 1Password, or call a destructive Transmission RPC in code-validation. The report-only configuration is the only live cleanup behavior until the user explicitly authorizes cutover and destructive activation.

## Deployment and cutover checklist (separately authorized)

The following operational actions are not part of code implementation or local validation. Perform them only after the user explicitly authorizes deployment/cutover:

1. Back up Ultra's Arr/Bazarr/Mylar3 state and verify backup restoration before changing any service.
2. Install/authorize Ultra's beta Tailscale app under the user's control, verify Prowlarr can reach only the intended Drlight Arr APIs over the tailnet, and keep Arr APIs closed to public ingress.
3. Switch on Drlight's Arr/Bazarr/Mylar3 services in report-only/download-disabled mode; restore state, remap the local roots, set the remote Transmission client, and test the local staging import path.
4. Cut over one app at a time. Keep old Ultra apps and data available until local library counts, Bazarr connections, Prowlarr indexer sync, and Transmission staging/import tests pass. Stop old Ultra Arr/Bazarr services only after that validation; retain backups for rollback.
5. Review cleanup's report-only candidates and the legacy organized-library inventory. Do not enable destructive cleanup or delete legacy files until the user separately approves that action and path ownership has been verified.

## Execution notes

- Follow TDD: write each behavior test before implementation, run RED, implement minimally, run GREEN.
- Use the existing policy evaluator and RPC adapter; review their committed changes before relying on them.
- Do not add the Nixarr framework or another flake input unless discovery shows it is necessary and the user approves the new dependency.
- Keep all app backups, secrets, hostnames, tracker identifiers, download paths, and runtime URLs outside Git.
- Use the repo's `jj` workflow and dedicated workspace; do not push or deploy.
