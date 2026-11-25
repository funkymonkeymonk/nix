# OpenChamber on Drlight Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Run OpenChamber and OpenCode on Drlight, reachable over LAN and tailnet through Caddy, using authenticated LAN Bifrost on MegamanX.

**Architecture:** Import the upstream OpenChamber NixOS module on Drlight and keep its listener loopback-only behind the existing HTTPS Caddy ingress. Extend MegamanX's Bifrost module with declarative inference and dashboard/admin authentication; bind it to all interfaces as explicitly selected and keep MegamanX Tailscale-disabled. Drlight's OpenCode provider reaches `megamanx:8081` over LAN.

**Tech Stack:** Nix flakes, upstream OpenChamber flake/NixOS module, Home Manager OpenCode role, nix-darwin LaunchDaemon, NixOS systemd, Opnix, Caddy, Nix evaluation checks.

**Spec:** `docs/superpowers/specs/2026-11-24-openchamber-drlight-design.md`

## Global Constraints

- Drlight remains the only Tailscale-enabled machine; MegamanX stays Tailscale-disabled.
- Bifrost binds to `0.0.0.0:8081` on MegamanX as selected by the user; require both inference virtual-key enforcement and dashboard/admin authentication.
- OpenChamber binds to `127.0.0.1:3001` on Drlight; expose it only through the existing Caddy app route.
- Use unqualified Opnix `Item/field` references through each machine's default `Opnix` vault; do not place secret values in Nix or generated store files.
- Preserve Bifrost's existing provider configuration and SQLite state while adding auth and the OpenChamber virtual key.
- Do not apply or deploy either machine configuration in this plan.
- Before a future deployment, verify `megamanx` resolves from Drlight to MegamanX's LAN address; stop if it does not.

## Review Focus

- **Bifrost config reconciliation:** adding auth must not remove existing `omlx` or `opencode-go` providers; test the rendered merged config in Task 1.
- **Secret leakage:** admin credentials, setup token, and virtual key must appear only as `env.*` references and runtime file reads; test absence of fixture values in Task 1.
- **Network boundary:** MegamanX must remain Tailscale-disabled and OpenChamber's raw port must remain closed; assert both in Tasks 2 and 3.
- **LAN/tailnet ingress:** Caddy must publish the OpenChamber hostname through existing DNS and retain its private-source filter; assert route, upstream, DNS record, and Caddy source policy in Task 3.
- **OpenCode endpoint:** Drlight must use the Anthropic-compatible Bifrost path and an Opnix file reference for its virtual key; assert generated OpenCode settings in Task 3.

---

### Task 1: Add declarative Bifrost authentication

**Files:**
- Modify: `tests/test-bifrost.nix`
- Modify: `tests/default.nix`
- Modify: `modules/services/bifrost/darwin.nix`
- Generated: `docs/reference/options.md`

**Interfaces:**
- Consumes: existing `myConfig.bifrost.upstreams`, launcher `configJson`, and Opnix-created secret files.
- Produces: `myConfig.bifrost.auth` with `enable`, `adminUsernameFile`, `adminPasswordFile`, `setupTokenFile`, and `virtualKey` fields (`id`, `name`, `valueFile`, `providers`).

- [ ] **Step 1: Write the failing Bifrost auth-config test**

  Add `bifrostNetworkAuthConfigTest` in `tests/test-bifrost.nix` and register it as `bifrost-network-auth` in `tests/default.nix`. Evaluate Bifrost with its existing `omlx` and `opencode-go` upstreams plus auth files and virtual key providers `['omlx' 'opencode-go']`. Parse the generated launcher `config.json` and assert `client.enforce_auth_on_inference == true`, dashboard/admin auth is enabled with inference auth not disabled, admin values are `env.*` references, and both existing provider entries remain. Assert the launcher exports `BIFROST_SETUP_TOKEN`, reads each configured secret file, and contains none of the fixture secret values.

- [ ] **Step 2: Run the check to verify it fails**

  Run: `devenv tasks run test:build-checks`  
  Expected: the new `bifrost-network-auth` check fails because the auth options/config are not implemented yet.

- [ ] **Step 3: Implement `myConfig.bifrost.auth` in `modules/services/bifrost/darwin.nix`**

  Add typed auth options and validation for required secret paths. Extend generated JSON with `client.enforce_auth_on_inference`, `governance.auth_config` (admin username/password references; `disable_auth_on_inference = false`), and one virtual key with the configured ID/name and allowed providers. Export the setup-token file as `BIFROST_SETUP_TOKEN`, as supported by Bifrost; extend the launcher to read the secret files into the matching `BIFROST_*` environment variables. Never interpolate secret values into Nix-generated JSON or scripts. Run `devenv tasks run docs:generate-options` and include the generated option reference update, because build checks verify it is current.

- [ ] **Step 4: Run the check to verify it passes**

  Run: `devenv tasks run test:build-checks`  
  Expected: `bifrost-network-auth` passes and the existing Bifrost checks remain green.

### Task 2: Configure authenticated LAN Bifrost on MegamanX

**Files:**
- Modify: `library/machines/catalog.nix`
- Modify: `tests/test-tailscale-config.nix`
- Modify: `tests/test-lydia-migration.nix`

**Interfaces:**
- Consumes: `myConfig.bifrost.auth` from Task 1.
- Produces: MegamanX Bifrost binds `0.0.0.0:8081`, auth is enabled with Opnix file paths, and `myConfig.tailscale.enable` remains `false`.

- [ ] **Step 1: Add failing resolved-MegamanX assertions**

  Extend the MegamanX section of `tests/test-tailscale-config.nix` to assert Tailscale stays disabled, Bifrost's host is `0.0.0.0`, auth is enabled, the virtual key allows only `omlx` and `opencode-go`, and the four secret references are unqualified references resolved through `Opnix`. Update the existing `tests/test-lydia-migration.nix` Bifrost host expectation from `127.0.0.1` to `0.0.0.0` so its machine-profile assertion matches the approved LAN listener.

- [ ] **Step 2: Run the focused test to verify it fails**

  Run: `devenv tasks run test:build-checks`  
  Expected: the new MegamanX Bifrost assertions fail against the current loopback-only configuration.

- [ ] **Step 3: Wire MegamanX Bifrost and Opnix references**

  In `library/machines/catalog.nix`, set the host to `0.0.0.0` and configure `auth` paths under `/var/run` for the admin username, admin password, setup token, and OpenChamber virtual key. Add matching unqualified Opnix references (`Bifrost Admin Username/username`, `Bifrost Admin Password/password`, `Bifrost Setup Token/credential`, and `Bifrost OpenChamber API Key/credential`) with restrictive permissions and Bifrost service restart dependencies. Do not alter MegamanX's `tailscale.enable = false`.

- [ ] **Step 4: Run the focused test to verify it passes**

  Run: `devenv tasks run test:build-checks`  
  Expected: MegamanX resolves with the authenticated all-interface Bifrost listener and no Tailscale service.

### Task 3: Add OpenChamber to Drlight and expose it through Caddy

**Files:**
- Modify: `flake.nix`
- Modify: `flake.lock`
- Modify: `library/machines/catalog.nix`
- Modify: `machines/drlight/default.nix`
- Modify: `modules/services/caddy/nixos.nix`
- Modify: `tests/test-media-center-archetype.nix`
- Generated: `docs/reference/options.md`

**Interfaces:**
- Consumes: Bifrost authentication and the virtual key configured in Tasks 1-2.
- Produces: `services.openchamber` on Drlight (`user = "monkey"`, `host = "127.0.0.1"`, `port = 3001`, `uiPasswordFile = "/run/secrets/openchamber-ui-password"`), a Caddy route, and Drlight OpenCode settings for `http://megamanx:8081/anthropic/v1`.

- [ ] **Step 1: Add failing Drlight integration assertions**

  Extend `drlightMediaPresentationTest` in `tests/test-media-center-archetype.nix`: expect the `openchamber` Caddy app at `openchamber.home.buildingbananas.com` with upstream `http://127.0.0.1:3001`; assert its generated virtual host contains `flush_interval -1`, the shared `@external` private-source matcher, and `respond @external 403`; assert its DNS host record is generated; assert the resolved OpenChamber service uses loopback, port 3001, user `monkey`, and systemd `LoadCredential`; assert port 3001 is not opened globally or on `eno1`; and assert Drlight's generated OpenCode provider uses the remote Anthropic URL and an Opnix API-key file reference. Update the Caddy/Homepage expected route/app/upstream lists.

- [ ] **Step 2: Run the check to verify it fails**

  Run: `devenv tasks run test:build-checks`  
  Expected: `drlight-media-presentation` fails because the OpenChamber service and Caddy app do not yet exist.

- [ ] **Step 3: Add and lock the upstream OpenChamber input**

  Add `openchamber.url = "github:openchamber/openchamber"` and `openchamber.inputs.nixpkgs.follows = "nixpkgs"` in `flake.nix`. Describe/commit this tracked input change before running Nix, then run `nix flake lock` and describe the resulting `flake.lock` update. Confirm the locked flake has the `x86_64-linux` package and NixOS module used by Drlight.

- [ ] **Step 4: Import the OpenChamber module and configure Drlight**

  Add `inputs.openchamber.nixosModules.openchamber` to Drlight's module list in `library/machines/catalog.nix`. In `modules/services/caddy/nixos.nix`, add a nullable integer `flushInterval` app option and emit `flush_interval` in generated `reverse_proxy` blocks when set. In `machines/drlight/default.nix`, enable the OpenChamber NixOS service for `monkey` on `127.0.0.1:3001` with `/run/secrets/openchamber-ui-password`; add the Opnix UI-password reference; enable `roles.opencode`; set `llmClient.serverHost = "megamanx"` and `serverPort = "8081"`; configure `local-bifrost` to use `http://megamanx:8081/anthropic/v1` and `Bifrost OpenChamber API Key/credential`; and add the Caddy app `openchamber.home.buildingbananas.com` proxying to loopback port 3001 with `flushInterval = -1`. Keep `services.openchamber.openFirewall` disabled. Run `devenv tasks run docs:generate-options` after the module integration and include the generated reference update.

- [ ] **Step 5: Run the integration check to verify it passes**

  Run: `devenv tasks run test:build-checks`  
  Expected: the Drlight service, Home Manager provider, Caddy route, DNS record, and no-direct-port assertions pass.

### Task 4: Align LLM documentation and run final validation

**Files:**
- Modify: `docs/reference/llm-stack.md`
- Modify: `docs/how-to/enroll-megamanx-in-tailscale.md`
- Modify: `tests/test-tailscale-config.nix`

**Interfaces:**
- Consumes: the resolved MegamanX/Drlight configuration from Tasks 2-3.
- Produces: reader-facing guidance matching LAN Bifrost, authenticated OpenChamber, Drlight Caddy ingress, and MegamanX's disabled Tailscale policy.

- [ ] **Step 1: Update the LLM stack reference and MegamanX enrollment guide**

  Document `openchamber.home.buildingbananas.com` for LAN/tailnet access, Drlight's loopback OpenChamber service, Bifrost's authenticated `megamanx:8081` LAN endpoint, and the all-interface binding caveat. Add a prominent notice to `docs/how-to/enroll-megamanx-in-tailscale.md` that MegamanX is intentionally Tailscale-disabled in the current setup and the OAuth procedure is only for a future, separately approved change. Extend `tests/test-tailscale-config.nix` to assert the notice while retaining its checks for the optional OAuth procedure.

- [ ] **Step 2: Run lint and the full test suite**

  Run: `devenv tasks run check:lint`, `devenv tasks run test:build-checks`, `devenv tasks run test:eval`, then `devenv tasks run test:all`.  
  Expected: all commands pass, including Drlight evaluation and the Bifrost/OpenChamber tests.

- [ ] **Step 3: Review and describe the completed configuration**

  Review the diff for accidental secret values, any Tailscale enablement on MegamanX, any global opening of port 3001, and any Bifrost provider/database replacement. Describe the final JJ change with a conventional `feat:` message and run `jj new`. Do not deploy; deployment requires a separate reviewed `machines:plan`/`machines:apply` request.
