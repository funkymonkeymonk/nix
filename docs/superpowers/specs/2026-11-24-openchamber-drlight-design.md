# OpenChamber on Drlight with LAN Bifrost

**Status:** Approved for implementation  
**Date:** 2026-11-24

## Intent

Provide a persistent OpenChamber workspace reachable from the home LAN and tailnet. OpenCode sessions, project checkouts, and shell commands run on Drlight. MegamanX remains Tailscale-disabled and serves Bifrost to Drlight over the LAN.

## Goals

- Run OpenChamber and its managed OpenCode server declaratively on Drlight.
- Serve the UI at `https://openchamber.home.buildingbananas.com` from LAN-only and tailnet clients through Drlight's Caddy ingress and interface-aware DNS.
- Keep OpenChamber bound to loopback, password-protected, and on a port other than Grafana's `3000`.
- Let Drlight reach Bifrost on MegamanX at `megamanx:8081` using a Bifrost virtual key.
- Keep MegamanX Tailscale-disabled; use the user-selected `0.0.0.0` Bifrost bind and protect inference plus dashboard/admin APIs with authentication.
- Store credentials in the machines' default Opnix vault; keep secret values out of Nix source and the store.
- Preserve Bifrost's existing SQLite/provider configuration while reconciling the auth and virtual-key settings.

## Non-goals

- Do not deploy or apply either machine configuration in this change.
- Do not enable Tailscale on MegamanX, configure Funnel, or add a Bifrost Caddy route.
- Do not expose the OpenChamber listener directly; Caddy is its only ingress.

## Approaches

1. **Selected:** OpenChamber and OpenCode on Drlight, Caddy as the HTTPS LAN/tailnet ingress, and authenticated Bifrost on MegamanX's network listener. Drlight's interface-aware DNS returns its LAN address for LAN queries and its Tailscale address for tailnet queries. This reuses Drlight's existing DNS/Caddy services and runs coding work on the selected host.
2. Expose OpenChamber's own HTTP port and separately add a Tailscale Serve adapter. This duplicates ingress, bypasses Caddy's TLS/source filtering, and requires new NixOS Serve support.
3. Keep OpenChamber on MegamanX and proxy it through Drlight. This puts projects and commands on the wrong host and adds a remote app hop.

## Design

- Add and lock the upstream OpenChamber flake. Import its NixOS module for Drlight and run the service as `monkey` on `127.0.0.1:3001`.
- Add `openchamber.home.buildingbananas.com` to Drlight's existing Caddy app configuration with upstream `http://127.0.0.1:3001` and `flush_interval -1` for SSE streaming. Drlight's dnsmasq returns the `eno1` address for LAN queries and the `tailscale0` address for tailnet queries. Caddy supplies TLS and rejects public source addresses.
- Enable the OpenCode role on Drlight. Configure its Bifrost provider to use `http://megamanx:8081/anthropic/v1` and the Opnix-managed virtual key. Set an OpenChamber UI password using Drlight's default Opnix vault.
- On MegamanX, leave Tailscale disabled and configure Bifrost to bind `0.0.0.0:8081` as explicitly selected by the user. Because this listens on all interfaces, require inference virtual-key enforcement and Bifrost dashboard/admin authentication. Use Opnix-managed admin username, password, setup token, and virtual key; no values are embedded in generated configuration.
- Verify before a later deployment that `megamanx` resolves from Drlight to MegamanX's LAN address. If it does not, stop and obtain the correct LAN endpoint.

## LAN DNS correction

Review found that Drlight's current DNS records return only `100.89.187.92`, its Tailscale address. Listening for DNS queries on `eno1` does not make that address reachable to LAN-only clients. Drlight receives its LAN address through DHCP, so the repository does not contain a stable LAN address to publish.

The selected correction uses dnsmasq `interface-name` records for `eno1` and `tailscale0`, with `localise-queries` enabled. Dnsmasq can then return the address for the interface that received each query. LAN clients already send `home.buildingbananas.com` DNS queries to Drlight's dnsmasq. This change does not modify router or DHCP configuration.

Other approaches considered:

1. Configure a reserved LAN address and publish it with the Tailscale address. This is simple, but needs an address reservation and would add machine-specific address state.
2. Keep the Tailscale-only answer and require LAN clients to run Tailscale. This preserves current DNS, but does not meet the LAN-only access goal.

Keep the Zero-hosted Sunshine record unchanged. Test that each Caddy hostname has interface-aware DNS records and that dnsmasq accepts the generated configuration.

## Security and verification

Test generated Bifrost JSON and launcher environment references without embedding fixture secrets. Confirm the existing Bifrost providers remain present, the Drlight Caddy route remains limited to private/tailnet sources, the OpenChamber raw port is not opened, and MegamanX remains Tailscale-disabled. Run repository lint, build-check, and configuration evaluation tasks. Deployment remains a separate, reviewed Machines plan/apply operation.
