---
title: "Enroll MegamanX in Tailscale"
description: "Join the boot-managed MegamanX inference server to the tailnet"
type: how-to
---

# Enroll MegamanX in Tailscale

MegamanX uses the same deployment-generated Tailscale OAuth key flow as the
NixOS servers. The named `machines:apply` operation checks the node state and
creates a preauthorized, non-reusable key only when Tailscale reports
`NeedsLogin`. The key uses MegamanX's catalogued `tag:home-lab` tag, is staged
only for activation, and is removed after enrollment. It is not printed or
stored in the Nix store. If the target state is unknown, the deployment fails
closed instead of creating a key.

No manual `tailscale up` command or pasted auth key is needed. macOS may still
require one-time approval of the Tailscale network extension/VPN configuration
in System Settings before the daemon can connect.

## Apply the reviewed MegamanX configuration

1. From the Nix configuration workspace, check the named target:

   ```bash
   devenv tasks run machines:check --input machine=MegamanX
   ```

2. Create and review a plan for MegamanX only:

   ```bash
   devenv tasks run machines:plan --input machine=MegamanX
   ```

   Confirm the plan targets `MegamanX` and review all proposed changes before
   proceeding. Stop if the target or changes are unexpected.

3. Apply the exact plan ID returned by `machines:plan`:

   ```bash
   devenv tasks run machines:apply \
     --input machine=MegamanX \
     --input planId=plan-<reviewed-plan-id>
   ```

   The wrapper stages a short-lived OAuth key only if the node reports
   `NeedsLogin`, waits for Tailscale to report `Running`, and cleans up the
   staged key on success or failure. It never includes the key in command
   arguments or output. Do not use `--yes` to bypass the plan review.

## Verify Tailscale and Bifrost

On MegamanX, confirm the daemon is running and has an IPv4 tailnet address:

```bash
sudo /run/current-system/sw/bin/tailscale status
sudo /run/current-system/sw/bin/tailscale ip -4
sudo /run/current-system/sw/bin/tailscale serve status
```

The Tailscale Serve mapping publishes the loopback-bound Bifrost API to the
tailnet on HTTP port `8081`. From an authorized tailnet device, verify:

```bash
curl --fail http://megamanx:8081/v1/models
```

The response should include the local oMLX model, `omlx/qwen3.8-27b`. Bifrost
remains bound to `127.0.0.1` on MegamanX; do not expose port `8081` directly on
the LAN or configure Tailscale Funnel. Tailnet ACLs must allow the intended
clients to reach MegamanX on TCP port `8081`.

## Verify existing telemetry paths

From Drlight, check MagicDNS and MegamanX's Tailscale-only node-exporter
endpoint:

```bash
getent hosts megamanx
curl --fail http://megamanx:9100/metrics
```

Prometheus on Drlight generates its node targets from the machine catalog and
should list MegamanX as active. Vector on MegamanX sends logs to Drlight's Loki
endpoint over Tailscale. The tailnet policy must permit the required paths:
Drlight to MegamanX on TCP ports `9100` and `8081`, and MegamanX to Drlight's
Loki endpoint on TCP port `3100`.

After enrollment, the nix-darwin system LaunchDaemon manages `tailscaled` at
boot without requiring a user LaunchAgent or interactive Tailscale sign-in.
The node exporter waits for Tailscale before binding, and the Tailscale Serve
LaunchDaemon waits for both a tailnet IP and Bifrost readiness before
publishing the API.
