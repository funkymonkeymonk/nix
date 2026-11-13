# Centralized Cross-Platform Tailscale Configuration

**Status:** Approved for implementation  
**Date:** 2026-11-12

## Intent

Give every Tailscale-enabled machine one declarative policy and the same unattended enrollment method, while using each OS's native service manager and package. All enabled machines will use Drlight's deployment-generated Tailscale OAuth auth keys. General-purpose hosts use `tag:home-lab`; Drlight retains `tag:home-lab` and `tag:media-center`.

## Goals

- Define shared Tailscale policy once: enablement, tags, advertised routes, exit-node setting, and Serve mappings.
- Automatically enroll NixOS and Darwin machines with preauthorized, non-reusable OAuth-generated auth keys during named deployment operations.
- Keep OAuth client credentials in per-machine SecretSpec profiles and generated auth keys in restricted runtime files only; never put resolved values in the Nix store or logs.
- Centralize Bifrost's Tailscale Serve mapping instead of keeping Tailscale CLI setup in the Bifrost module.
- Preserve loopback-only service binding and tailnet-only publication; do not enable Funnel or public exposure.

## Non-goals

- Rotating the Tailscale OAuth client credentials or auth-key policy.
- Changing Bifrost or oMLX model behavior or local bind addresses.
- Automatically deploying these changes to any live machine.

## Approaches Considered

1. **Shared policy with OS-specific adapters (selected).** One common option set describes Tailscale policy. NixOS and Darwin adapters implement secret staging, daemon startup, authentication, and Serve using systemd or launchd. This centralizes policy without pretending the operating systems have identical service mechanisms.
2. **Centralize authentication only.** Keep Bifrost's Serve configuration in its service module. This is smaller, but leaves Tailscale configuration split across modules.
3. **Duplicate full configuration per OS.** This preserves current platform boundaries but does not remove policy duplication.

## Design

The existing `myConfig.tailscale` options remain the shared policy surface. The machine catalog is the source of truth for each machine's Tailscale enablement and tags, so deployment tooling can make safe decisions without evaluating a secret-bearing module graph. All enabled machines use deployment-generated OAuth keys; the old static Opnix auth-key path is removed after migration. Host-specific security policy remains expressed as tags: default to `tag:home-lab`, with Drlight additionally assigned `tag:media-center`.

- **OAuth key generation:** reuse `scripts/tailscale-oauth-authkey.sh`, generating a preauthorized, non-reusable key with the target machine's tags. The caller resolves Tailscale OAuth client credentials through that machine's SecretSpec profile. The key is staged only for an explicit `machines:deploy` or reviewed `machines:apply` operation when the target reports `NeedsLogin`; `Running` skips key generation, and empty or other backend states fail closed. After activation, the controller waits for the target to report `Running` before cleanup; failures and timeouts still remove the staged file.
- **NixOS adapter:** retain the existing `/run/devenv/tailscale-auth-key` handoff and systemd auto-connect behavior. The service consumes the staged key and removes it; the deployment wrapper also cleans up after success or failure.
- **Darwin adapter:** add equivalent unattended enrollment through nix-darwin activation/launchd. The deployment wrapper must support Darwin targets, stage the one-time key in a restricted runtime path readable by the privileged activation/service, and remove it on every exit path. The adapter waits for `tailscaled`, authenticates only from the known `NeedsLogin` state, avoids re-authenticating an already-connected node, fails closed on other/unknown states, and never falls back to interactive login.
- **Credential profiles:** keep OAuth client ID and secret in the approved Opnix SecretSpec provider. Add them to any custom machine profile that has Tailscale enabled (MegamanX currently has a custom profile); do not place values in Nix expressions. Use the machine's approved default-vault provider.
- **Shared Serve policy:** declare Bifrost's tailnet-only mapping under `myConfig.tailscale.serve` (port 8081 to `http://127.0.0.1:8081`). The Bifrost module keeps local binding and readiness behavior but no longer owns Tailscale CLI setup.
- **Startup order:** publication waits until Tailscale has an IP and Bifrost `/v1/models` is healthy. Serve is tailnet-only; Funnel is not configured.
- **Compatibility:** preserve existing exit-node and advertised-route options. OAuth tags must be non-empty and valid for every enabled machine.

## Acceptance Criteria

- Every machine with `myConfig.tailscale.enable` uses deployment-generated OAuth auth keys; static Opnix Tailscale auth-key references are removed from active configurations.
- General-purpose enabled machines have `tag:home-lab`; Drlight has both `tag:home-lab` and `tag:media-center`.
- NixOS and Darwin configurations evaluate with their respective native authentication services.
- Named deploy and reviewed apply operations generate and stage a key only when the target reports `NeedsLogin`, support both NixOS and Darwin, and clean up the staged key after success or failure.
- MegamanX's custom SecretSpec profile can resolve the existing OAuth client ID and secret from the approved Opnix provider without copying values into Nix.
- Bifrost's Serve mapping is represented under Tailscale configuration and is published only after local readiness; no public Funnel is configured.
- The existing NixOS authentication and Drlight tag behavior remain intact.
- Tests cover disconnected/connected targets, cleanup, invalid or missing OAuth profile data, Darwin staging/activation, NixOS activation, and centralized Serve configuration.
- The MegamanX enrollment guide documents deployment-based enrollment and no longer instructs a manual `tailscale up` flow.

## Validation Boundary

Do not deploy or authenticate any real machine during implementation. Validate with Nix evaluation, automated shell/module checks, and focused tests. Live deployment remains a separate, explicitly reviewed operation.
