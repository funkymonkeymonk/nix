---
title: "Enroll MegamanX in Tailscale"
description: "Join the boot-managed MegamanX inference server to the tailnet"
type: how-to
---

# Enroll MegamanX in Tailscale

Use this procedure once after deploying the MegamanX configuration. The Nix
configuration starts the Tailscale daemon at boot, but a new macOS device must
still be authorized interactively before it can join the tailnet.

1. Activate the Nix configuration on MegamanX and wait for the system
   LaunchDaemon to start:

   ```bash
   sudo launchctl print system/com.tailscale.tailscaled
   ```

2. In a terminal on MegamanX, start Tailscale enrollment:

   ```bash
   sudo /run/current-system/sw/bin/tailscale up
   ```

3. Open the authentication URL printed by the command and approve MegamanX for
   the tailnet. If macOS asks to approve a Tailscale network extension or VPN
   configuration, approve it in System Settings. Enable MagicDNS for the tailnet;
   the configured Vector and Prometheus targets use the short names `drlight`
   and `MegamanX`. The tailnet policy must allow drlight to reach MegamanX on
   TCP ports `9100` (Prometheus) and `8081` (Bifrost). It must also allow
   MegamanX to reach drlight's Loki endpoint on TCP port `3100`.

4. Confirm the node is connected and has a Tailscale IPv4 address:

   ```bash
   sudo /run/current-system/sw/bin/tailscale status
   sudo /run/current-system/sw/bin/tailscale ip -4
   ```

5. Confirm the boot-managed services became ready:

   ```bash
   sudo launchctl print system/org.prometheus.node-exporter
   sudo launchctl print system/com.bifrost.tailscale-serve
   curl http://127.0.0.1:8081/v1/models
   ```

6. On drlight, verify the tailnet name resolves and metrics are reachable:

   ```bash
   getent hosts MegamanX
   curl http://MegamanX:9100/metrics
   ```

   Prometheus on drlight generates its node targets from the machine catalog;
   it should list `MegamanX:9100` as an active target. Vector on MegamanX sends
   service logs to drlight's Loki endpoint over the tailnet.

After enrollment, the Nix-darwin system LaunchDaemon manages `tailscaled` at
boot rather than relying on a user LaunchAgent. Verify this behavior by rebooting
MegamanX without logging in. The node exporter waits for Tailscale before
binding, and the Tailscale Serve LaunchDaemon waits for both Tailscale and
Bifrost before publishing the API.
