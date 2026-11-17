# Pi Tailnet Bifrost Design

## Intent

Make Bifrost on MegamanX available to every Pi instance on the Tailscale tailnet, without enrolling machines that are not already tailnet members or changing Pi's current default provider/model selection.

## Goals and boundaries

- Tailnet-enabled Pi configurations use MegamanX's Tailscale Serve endpoint, `http://megamanx:8081/v1`.
- Pi configurations outside the tailnet retain their existing endpoint behavior.
- Keep other LLM clients' shared endpoint settings unchanged; this request is Pi-specific.
- Preserve existing defaults such as OpenCode Go. Bifrost becomes an available Pi provider/model, not the automatic default.
- Do not change Tailscale enrollment, Bifrost exposure, secrets, or machine deployment state.

## Approaches considered

1. **Tailnet-aware shared Pi default (selected):** derive the Pi Bifrost endpoint from the machine's existing Tailscale-enabled setting. This covers current tailnet Pi machines and future ones without duplicate per-host URL overrides.
2. **Per-machine overrides:** assign the MegamanX endpoint on each current tailnet Pi machine. This is explicit but easy to omit on future machines.

The shared rule is selected because the requested scope is defined by existing tailnet membership. Non-tailnet Pi machines, including Lydia and wweaver, remain unchanged.

## Constraints and implementation details

MegamanX binds Bifrost to loopback and publishes it to tailnet clients on HTTP port 8081. Do not bind Bifrost directly to a network interface or alter the Serve mapping. Pi's endpoint should be configured independently of `myConfig.llmClient`, which also affects OpenCode and Claude. Preserve explicit host-specific Pi provider/model settings while ensuring tailnet Pi instances, including Zero's explicitly customized model set, can use the Bifrost provider.

## Verification

Add or adjust configuration tests to confirm tailnet Pi instances point to `http://megamanx:8081/v1`, non-tailnet Pi configurations keep their current behavior, Bifrost is available on the customized Zero Pi configuration, and existing default provider/model choices are preserved. Run the repository lint and relevant evaluation/build checks.
