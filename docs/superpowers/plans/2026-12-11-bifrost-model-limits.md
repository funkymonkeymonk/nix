# Bifrost Model Limits Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Bifrost advertise OpenCode Go and OMLX model limits to Pi while enforcing a 32,000-token output cap for Pi-discovered models.

**Architecture:** Add Bifrost's native OpenCode Go provider using the existing Pi/Opnix-managed secret file and an environment-variable reference. Patch the pinned Bifrost source to preserve upstream `limit.context`/`limit.output` metadata and load a Nix-generated OMLX metadata file; update Pi discovery to map those fields into Pi model metadata with a 32K output cap.

**Tech Stack:** Nix/nix-darwin, existing Home Manager/Opnix secret, Bifrost Go source patch, Pi TypeScript extension, Nix runCommand tests, Node.js test for the pure metadata mapper.

**Spec:** `docs/superpowers/specs/2026-12-11-bifrost-model-limits-design.md`

## Global Constraints

- Keep API keys out of Nix-generated JSON and the Nix store; reuse the existing Pi/Opnix secret file backed by `OpenCode Service Account - MegamanX/credential` in the machine's `defaultVault`.
- Do not overwrite or reconcile Bifrost's existing SQLite provider/config state beyond adding the explicitly declared OpenCode Go provider.
- Keep Bifrost and oMLX listeners, current OMLX memory guard/concurrency/cache settings, and Tailscale exposure unchanged.
- Do not enable Bifrost dashboard auth or use its management API.
- Do not deploy or switch the live host.
- Set OMLX Qwen metadata to 128000 context tokens and 30720 max output tokens; cap Pi output at 32000 tokens for all discovered models.
- Use Jujutsu workspaces and commands; never mix Git and Jujutsu operations except `git add` for new files required by the flake.

## Review Focus

- OpenCode Go returns nested `limit.context`/`limit.output`, not only OpenAI's root `context_window`; the Bifrost parser must preserve those fields. Test: Go fixture with nested limits and exact values.
- Provider config must use `opencode-go` natively, not treat it as an OpenAI-compatible custom provider. Test: generated config structure has native provider key and no `custom_provider_config`.
- Secret values must never appear in Bifrost JSON or generated scripts; only an environment reference and secret-file path may appear. Test: generated config/script has env reference and never includes fixture secret contents.
- OMLX metadata must merge only when the upstream does not report a value, and be keyed to `omlx/qwen3.8-27b`. Test: Bifrost unit fixture preserves upstream metadata and fills missing values from the declared map.
- Pi's output cap must clamp large provider limits and use the fallback for absent values without reducing the advertised context window. Test: execute the pure mapper with large, small, and missing-limit fixtures.

---

### Task 1: Bifrost model-limit propagation

**Files:**
- Create: `packages/bifrost/patches/model-list-limits.patch`
- Modify: `overlays/default.nix`
- Test: Go tests included in the patch against Bifrost's pinned `core/providers/openai` and model-list conversion code.

**Interfaces:**
- Consumes: the existing Bifrost flake input pinned in `flake.lock` and its v2.5.1 package overlay.
- Produces: Bifrost `/v1/models` entries with `context_window` and `max_output_tokens` fields for provider-reported metadata, plus a loader for Nix-provided model metadata.

- [x] **Step 1: Add failing Bifrost source tests in the patch**

  Add a Go fixture for an OpenCode Go list-model record with `limit.context = 1000000` and `limit.output = 384000`; assert the Bifrost model carries `ContextLength == 1000000` and `MaxOutputTokens == 384000`. Add a serialization assertion that Bifrost's OpenAI-compatible list response emits those values. Add a model-catalog test that reads `BIFROST_MODEL_METADATA_FILE` for `omlx/qwen3.8-27b` with 128000/30720, asserting upstream values win and missing values are filled.

- [x] **Step 2: Run the focused Go tests to verify RED**

  The pinned `bifrost-http` derivation sets `doCheck = false`, so its package build does not run these regression tests. In a writable copy of the pinned Bifrost source with the test patch applied, run:
  - `nix shell nixpkgs#go -c bash -c 'cd /tmp/bifrost-model-limits-red/core && go test ./providers/openai'`
  - `nix shell nixpkgs#go -c bash -c 'cd /tmp/bifrost-model-limits-red/framework && go test ./modelcatalog'`
  Expected: nested limits are dropped, `max_output_tokens` is absent, and local OMLX metadata is not loaded.

- [x] **Step 3: Implement the Bifrost source patch**

  Parse nested `limit.context`/`limit.output`, map them to `schemas.Model.ContextLength`/`MaxOutputTokens`, serialize `context_window`/`max_output_tokens`, and load the Nix-provided metadata JSON map at startup, filling only absent model fields. Apply the patch through the existing `bifrost-http` package override without changing its version or dependency graph.

- [x] **Step 4: Run the focused Go tests and package build to verify GREEN**

  Run the two focused Go test commands from Step 2 against the patched writable source copy, then run `nix build .#packages.$(nix eval --impure --expr 'builtins.currentSystem' --raw).bifrost-http --no-link --impure`.
  Expected: both focused Go test packages pass and the Bifrost HTTP package builds.

### Task 2: Nix-managed Bifrost OpenCode Go provider and OMLX metadata

**Files:**
- Modify: `modules/services/bifrost/darwin.nix`
- Modify: `library/machines/catalog.nix`
- Modify: `tests/test-bifrost.nix`
- Modify: `tests/test-lydia-migration.nix` if needed for MegamanX assertions.

**Interfaces:**
- Consumes: Task 1's `BIFROST_MODEL_METADATA_FILE` loader and Bifrost model-list field names.
- Produces: a native Bifrost `opencode-go` provider using `env.BIFROST_OPENCODE_GO_API_KEY`, loading the existing user-owned Pi secret file, and a Nix-store metadata JSON file for `omlx/qwen3.8-27b` (128000/30720).

- [x] **Step 1: Add failing Nix evaluation tests**

  Assert that an OpenCode Go upstream generates a native `providers.opencode-go` entry with the `env.BIFROST_OPENCODE_GO_API_KEY` reference and no `custom_provider_config`. Assert that the launcher reads the configured `.pi/agent/secrets/opencode-go-apikey` file but never embeds a fixture secret value. Assert that the Nix-store metadata JSON referenced by `BIFROST_MODEL_METADATA_FILE` contains `omlx/qwen3.8-27b` with `context_length = 128000` and `max_output_tokens = 30720`.

- [x] **Step 2: Run focused tests to verify RED**

  Run: `nix build .#checks.$(nix eval --impure --expr 'builtins.currentSystem' --raw).bifrost-options .#checks.$(nix eval --impure --expr 'builtins.currentSystem' --raw).bifrost-opencode-go --no-link --impure`
  Expected: evaluation fails because the `opencode-go` provider type, `apiKeyFile`, and metadata options do not yet exist.

- [x] **Step 3: Add native-provider, metadata, and secret-file configuration**

  Add the `opencode-go` upstream type and native-provider config path. Add a relative `apiKeyFile` option; when set, generate the environment reference and load that existing user-owned Pi/Opnix secret file in the launch wrapper. Add a typed per-model `modelMetadata` option, serialize it with `pkgs.writeText`, and set `BIFROST_MODEL_METADATA_FILE` to that store path. Configure MegamanX to point at `.pi/agent/secrets/opencode-go-apikey` and set Qwen's OMLX metadata to 128000/30720.

- [x] **Step 4: Run focused tests to verify GREEN**

  Run: `nix build .#checks.$(nix eval --impure --expr 'builtins.currentSystem' --raw).bifrost-options .#checks.$(nix eval --impure --expr 'builtins.currentSystem' --raw).bifrost-opencode-go --no-link --impure`
  Expected: all generated-config, secret-file, and metadata assertions pass.

### Task 3: Pi discovery mapping and output cap

**Files:**
- Create: `modules/home-manager/bifrost-model-metadata.mjs`
- Modify: `modules/home-manager/pi-coding-agent.nix`
- Modify: `modules/roles/pi.nix`
- Modify: `tests/test-pi.nix`

**Interfaces:**
- Consumes: Bifrost's `/v1/models` records containing `context_window` and `max_output_tokens` from Tasks 1–2.
- Produces: a pure `mapBifrostModel(model)` helper used by the discovery extension; its returned Pi model uses the advertised context (fallback 128000) and `maxTokens = min(advertised output limit or 32000, 32000)`.

- [x] **Step 1: Add a failing executable mapper test**

  Run the real `.mjs` helper with Node fixtures. Assert that `context_window=1000000,max_output_tokens=384000` maps to `contextWindow=1000000,maxTokens=32000`; `context_length=128000,max_output_tokens=30720` maps to `128000/30720`; `max_output_tokens=4096` remains 4096; and missing values use 128000/32000.

- [x] **Step 2: Run the helper test to verify RED**

  Run the focused `test-pi` check with `--impure`.
  Expected: it fails because the helper and metadata mapping do not exist.

- [x] **Step 3: Implement and wire the mapper**

  Write the pure helper, include it beside the discovery extension, and use it for every model returned by Bifrost. Keep the Bifrost provider in Pi discovery-only mode so its generated model metadata comes from `/v1/models`, not a duplicate Pi-side hardcoded model entry.

- [x] **Step 4: Run the helper and Pi configuration tests to verify GREEN**

  Run: `nix build .#checks.$(nix eval --impure --expr 'builtins.currentSystem' --raw).pi-options .#checks.$(nix eval --impure --expr 'builtins.currentSystem' --raw).pi-bifrost-metadata --no-link --impure`
  Expected: all mapper and generated Pi configuration assertions pass.

### Task 4: Documentation and validation

**Files:**
- Modify: `docs/reference/llm-stack.md`
- Modify: `docs/reference/options.md` if the new Bifrost options require reference documentation.

- [x] **Step 1: Document model metadata ownership and verification**

  Explain that OpenCode Go limits are read from Bifrost's model list, OMLX limits are declared in Bifrost's Nix model metadata, Pi caps output at 32K, and how to inspect `/v1/models` for the advertised fields. Note that this does not change runtime OMLX context allocation.

- [ ] **Step 2: Run formatting and focused checks**

  Run `devenv tasks run check:lint`, the focused Bifrost/Pi checks, and `devenv tasks run test:build-checks` after staging and describing the intended JJ revision so flake evaluation reads the committed tree.
  Expected: all checks pass. The baseline lint currently reports the pre-existing `overlays/default.nix` formatting change; format that file while preserving the existing `postPatch` behavior, then rerun lint.

- [ ] **Step 3: Build the Bifrost package**

  Run the current-system Bifrost package build and inspect the final JJ diff/status. Do not switch or deploy the live machine.
