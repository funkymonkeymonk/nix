# OpenChamber on Drlight with LAN Bifrost

**Status:** Approved for implementation  
**Date:** 2026-11-24

## Intent

Provide a persistent OpenChamber workspace reachable from the home LAN and tailnet. OpenCode sessions, project checkouts, and shell commands run on Drlight. MegamanX remains Tailscale-disabled and serves Bifrost to Drlight over the LAN.

## Goals

- Run OpenChamber and its managed OpenCode server declaratively on Drlight.
- Serve the UI at `https://openchamber.home.buildingbananas.com` from LAN and tailnet clients through Drlight's existing Caddy and DNS configuration.
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

1. **Selected:** OpenChamber and OpenCode on Drlight, Caddy as the HTTPS LAN/tailnet ingress, and authenticated Bifrost on MegamanX's network listener. This reuses Drlight's established DNS/Caddy ingress and runs coding work on the selected host.
2. Expose OpenChamber's own HTTP port and separately add a Tailscale Serve adapter. This duplicates ingress, bypasses Caddy's TLS/source filtering, and requires new NixOS Serve support.
3. Keep OpenChamber on MegamanX and proxy it through Drlight. This puts projects and commands on the wrong host and adds a remote app hop.

## Design

- Add and lock the upstream OpenChamber flake. Import its NixOS module for Drlight and run the service as `monkey` on `127.0.0.1:3001`.
- Add `openchamber.home.buildingbananas.com` to Drlight's existing Caddy app configuration with upstream `http://127.0.0.1:3001` and `flush_interval -1` for SSE streaming. Existing DNS publishes Caddy app names to Drlight on both interfaces; Caddy supplies TLS and rejects public source addresses.
- Enable the OpenCode role on Drlight. Configure its Bifrost provider to use `http://megamanx:8081/anthropic/v1` and the Opnix-managed virtual key. Set an OpenChamber UI password using Drlight's default Opnix vault.
- On MegamanX, leave Tailscale disabled and configure Bifrost to bind `0.0.0.0:8081` as explicitly selected by the user. Because this listens on all interfaces, require inference virtual-key enforcement and Bifrost dashboard/admin authentication. Use Opnix-managed admin username, password, setup token, and virtual key; no values are embedded in generated configuration.
- Verify before a later deployment that `megamanx` resolves from Drlight to MegamanX's LAN address. If it does not, stop and obtain the correct LAN endpoint.

## Security and verification

Test generated Bifrost JSON and launcher environment references without embedding fixture secrets. Confirm the existing Bifrost providers remain present, the Drlight Caddy route remains limited to private/tailnet sources, the OpenChamber raw port is not opened, and MegamanX remains Tailscale-disabled. Run repository lint, build-check, and configuration evaluation tasks. Deployment remains a separate, reviewed Machines plan/apply operation.
