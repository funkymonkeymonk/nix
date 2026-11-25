---
title: "LLM Stack Reference"
description: "Architecture and operations for the local oMLX and Bifrost inference stack"
type: reference
---

# LLM Stack Reference

## Architecture

Applications connect to Bifrost, which routes model requests to oMLX.

| Layer | Local endpoint | Remote access |
|---|---|---|
| Inference | `http://127.0.0.1:8300` on MegamanX | Loopback only; access through Bifrost |
| Gateway | Bifrost `0.0.0.0:8081` on MegamanX | LAN clients use `http://megamanx:8081`; inference and dashboard/admin routes require authentication |
| OpenChamber | `http://127.0.0.1:3001` on Drlight | `https://openchamber.home.buildingbananas.com` from LAN and tailnet through Caddy |
| Application logs | Vector on MegamanX | Sent to Loki on Drlight |
| Host metrics | node_exporter on MegamanX | Loopback-only while MegamanX is Tailscale-disabled |
| Central metrics | Prometheus on Drlight | Includes the catalog target `MegamanX:9100`; it remains unavailable remotely while MegamanX's exporter is loopback-bound |

Only Drlight joins the Tailscale network. MegamanX intentionally remains
Tailscale-disabled; Drlight reaches MegamanX's Bifrost through the local LAN
hostname `megamanx`. OpenCode sessions and project commands run on Drlight.
Verify that `megamanx` resolves to MegamanX's LAN address before deployment.

Drlight's dnsmasq listens on the LAN (`eno1`) and tailnet (`tailscale0`). It uses
interface-aware records for Caddy apps and returns the address of the interface
that received each DNS query. The LAN address follows Drlight's DHCP lease, so
Nix does not need a fixed LAN address. LAN clients must use Drlight's dnsmasq for
`home.buildingbananas.com` names. Caddy provides HTTPS and rejects public source
addresses. OpenChamber stays bound to loopback behind Caddy, with its UI password
stored in Opnix. Its Caddy route uses `flush_interval -1` for live SSE updates.

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

Bifrost runs as a system LaunchDaemon on port `8081`, bound to `0.0.0.0` on
MegamanX so Drlight can reach it over the LAN. This is an all-interface bind,
not a LAN-only bind; do not create a router port-forward for this port. Inference
requests require the OpenChamber virtual key, and the dashboard/admin API require
separate Bifrost credentials. Both are referenced from Opnix, not embedded in
Nix. MegamanX does not run Tailscale, and Bifrost is not published through
Tailscale Serve.

The local Caddy route remains available on MegamanX at `http://bifrost.internal`
and rejects non-local clients. Bifrost is not published through Tailscale Serve
or a Drlight Caddy route; Drlight's OpenCode provider uses
`http://megamanx:8081/anthropic/v1` directly over the LAN.

```bash
sudo launchctl print system/com.bifrost.service
curl http://127.0.0.1:8081/health
```

Use `omlx/qwen3.8-27b` as the model ID through Bifrost. Bifrost also exposes
OpenCode Go's subscription models under the `opencode-go/` prefix. Bifrost reads
the OpenCode Go upstream credential from the existing Pi/Opnix secret file. The
client-facing virtual key is a separate Opnix secret; do not put either value in
Nix configuration.

Bifrost advertises OpenCode Go's context and output limits in `/v1/models`.
Nix sets Qwen OMLX's advertised limits because oMLX does not report them. The
limits are 128,000 context tokens and 30,720 output tokens. Pi uses the
advertised context window and caps output at 32,000 tokens. These are client
limits. They do not change oMLX's runtime allocation or guarantee that every
context size fits available memory.

Inspect the limits that Bifrost advertises:

```bash
curl -s http://127.0.0.1:8081/v1/models \
  -H "x-api-key: $BIFROST_OPENCHAMBER_API_KEY" \
  | jq '.data[] | select(.id == "omlx/qwen3.8-27b" or (.id | startswith("opencode-go/"))) | {id, context_window, max_output_tokens}'
```

Set `BIFROST_OPENCHAMBER_API_KEY` from the Opnix-managed file before running
this request; do not print or commit the key.

The upstream's `streamIdleTimeoutInSeconds` is configured to accommodate long
prompt prefills.

## LAN and tailnet operations

The MegamanX Tailscale enrollment guide is an optional future procedure and is
not part of the current OpenChamber/Bifrost setup. See
[Enroll MegamanX in Tailscale](../how-to/enroll-megamanx-in-tailscale.md) for
its warning and approval boundary.

Before a future deployment, verify from Drlight that `megamanx` resolves to
MegamanX's LAN address. Do not infer or hard-code an address from an old
deployment note. Once the LAN route is available, Drlight's OpenCode provider
uses the Opnix virtual key for Bifrost requests. The Bifrost dashboard/admin
credentials are separate from the inference virtual key.

MegamanX's node exporter remains loopback-bound while Tailscale is disabled, so
the Drlight Prometheus inventory can list `MegamanX:9100` while the target is
unavailable remotely. Vector continues to send service logs to Drlight's Loki
using the configured collector hostname.

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

MegamanX is intentionally Tailscale-disabled in this setup; use the LAN Bifrost
path documented above. Do not follow the optional enrollment procedure unless a
separately approved design requires MegamanX to join the tailnet.
