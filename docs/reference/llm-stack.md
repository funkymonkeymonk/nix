---
title: "LLM Stack Reference"
description: "Architecture and operations for the local oMLX and Bifrost inference stack"
type: reference
---

# LLM Stack Reference

## Architecture

Applications connect to Bifrost, which routes model requests to oMLX.

| Layer | Local endpoint | Tailnet access |
|---|---|---|
| Inference | `http://127.0.0.1:8300` | Loopback only; access through Bifrost |
| Gateway | `http://127.0.0.1:8081` | `http://MegamanX:8081` through Tailscale Serve |
| Application logs | Vector on MegamanX | Sent to Loki on `drlight:3100` |
| Host metrics | node_exporter on MegamanX | Bound to its Tailscale IPv4 address on port `9100` |
| Central metrics | Prometheus on drlight | Scrapes the catalog target `MegamanX:9100` |

MegamanX and drlight join the same Tailscale network. Tailscale Serve is the
remote path to Bifrost; the local Bifrost and oMLX listeners are not exposed on
MegamanX's LAN interfaces. MegamanX's Caddy `bifrost.internal` route also
rejects non-local clients.

The model is fetched and exposed by Nix at the stable alias `qwen3.8-27b`.
Bifrost exposes it as `omlx/qwen3.8-27b`.

## oMLX

The Darwin service is declared in `modules/services/omlx/darwin.nix`. It runs
as the primary user in the system LaunchDaemon domain, starts at boot, and is
restarted by launchd after process failure. Its launcher probes `/health` for up
to 600 seconds and exits unsuccessfully if the server stays alive without
becoming ready; this lets launchd recover from a wedged startup. The configured
maximum concurrency is four requests.

The oMLX API binds to `127.0.0.1:8300`; clients use Bifrost instead of reaching
the inference server directly. oMLX uses continuous batching, hot KV caching,
and SSD-backed cache storage.

Useful checks on MegamanX:

```bash
sudo launchctl print system/org.omlx.server
curl http://127.0.0.1:8300/health
curl http://127.0.0.1:8300/v1/models
```

Logs are in `~/Library/Logs/omlx/` and `~/.omlx/logs/`. Vector ships those
files, along with `/tmp/*.log`, to drlight.

The current nixpkgs input has no oMLX package and upstream does not publish a
Nix flake, so oMLX remains the Homebrew exception. Nix manages the formula
selection and disables Homebrew auto-update and activation-time upgrades. Update
oMLX deliberately, then smoke-test boot readiness and inference before keeping
the new version.

## Bifrost

Bifrost runs as a system LaunchDaemon on port `8081`, bound to loopback on
MegamanX. A second Nix-managed LaunchDaemon waits for Tailscale and the local
Bifrost API, then configures `tailscale serve --bg --http=8081` to proxy the
loopback service to the tailnet. The Tailscale Serve endpoint is private to the
tailnet and governed by its access policy.

The local Caddy route remains available to local applications at
`http://bifrost.internal`. It rejects non-local clients so it cannot bypass the
Tailscale-only remote route.

```bash
sudo launchctl print system/com.bifrost.service
sudo launchctl print system/com.bifrost.tailscale-serve
curl http://127.0.0.1:8081/v1/models
```

Use `omlx/qwen3.8-27b` as the model ID through Bifrost. The upstream's
`streamIdleTimeoutInSeconds` is configured to accommodate long prompt prefills.

## Tailscale and telemetry

The nix-darwin `services.tailscale` module starts `tailscaled` at boot on
MegamanX. Drlight retains its NixOS Tailscale auto-connect configuration. A
one-time interactive enrollment is still required for a new MegamanX node; see
[Enroll MegamanX in Tailscale](../how-to/enroll-megamanx-in-tailscale.md). The
Nix-darwin system daemon is configured to run at boot, independent of a user
LaunchAgent; verify the first reboot with no user logged in on MegamanX.

MegamanX's Vector daemon sends system and oMLX logs to drlight's Loki service.
The node exporter waits for Tailscale, resolves the assigned IPv4 address, and
binds only to that address. Drlight's Prometheus target list is generated from
the machine catalog and includes `MegamanX:9100`.

Verify connectivity after enrollment:

```bash
# On MegamanX
sudo tailscale status
sudo tailscale ip -4
curl http://127.0.0.1:8081/v1/models

# On drlight
getent hosts MegamanX
curl http://MegamanX:9100/metrics
curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | select(.labels.job == "node")'
```

## Troubleshooting

If oMLX is not ready, inspect its system LaunchDaemon and logs:

```bash
sudo launchctl print system/org.omlx.server
cat ~/Library/Logs/omlx/server.error.log
cat ~/.omlx/logs/server.log
```

If the model is not listed, verify the Nix-managed model link:

```bash
readlink ~/.omlx/models/qwen3.8-27b
```

If Tailscale has not authenticated MegamanX yet, enroll it once as described in
the how-to guide. The node-exporter service deliberately waits for a Tailscale
IPv4 address before listening; Vector retries its Loki sink until drlight is
reachable.
