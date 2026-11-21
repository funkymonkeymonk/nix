# Drlight as the Singular Tailscale Gateway

**Status:** Approved for implementation  
**Date:** 2026-11-20

## Intent

Make Drlight the only Tailscale-enabled machine. Services that Drlight
currently exposes only through `tailscale0` must also be reachable from the
home LAN without opening them globally.

## Goals

- Disable Tailscale on every catalog machine except Drlight.
- Preserve Drlight's Tailscale tags and existing tailnet service behavior.
- Expose Drlight's Tailscale-only service ports on the configured LAN interface
  as well as `tailscale0`.
- Make Drlight's home DNS service listen on both Tailscale and LAN interfaces.
- Remove obsolete Tailscale-dependent configuration from machines that no
  longer run Tailscale.

## Non-goals

- Do not expose these services on every interface or globally open their ports.
- Do not turn Drlight into a general-purpose subnet router for arbitrary LAN
  devices unless an existing route configuration already requires it.
- Do not deploy or authenticate any live machine.

## Approach

Use explicit dual-interface firewall policy. Existing `tailscale0` rules remain
unchanged; Drlight adds the same service ports to the LAN interface only. The
DNS module changes its dnsmasq interface list from `tailscale0` to the LAN
interface plus `tailscale0`, while retaining its restricted firewall rules.
Catalog overrides set `tailscale.enable = false` for all other currently
enabled machines and remove their Tailscale-only service settings.

The LAN interface is identified from the repository's Drlight hardware/network
configuration rather than inferred at runtime. Tests will assert the catalog
enablement boundary, Drlight LAN firewall exposure, dual-interface DNS
configuration, and removal of non-Drlight Serve configuration.

## Remaining implementation calls

- Preserve existing service-specific opt-in semantics and derive LAN rules from
  the same configured ports, avoiding duplicated port lists where practical.
- Keep Drlight's current stable Tailscale DNS records; LAN clients receive the
  same service names through the dual-interface dnsmasq listener.
