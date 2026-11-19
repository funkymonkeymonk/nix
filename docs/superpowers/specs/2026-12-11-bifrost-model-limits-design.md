# Bifrost Model Limits Design

## Goal

Make Bifrost the model-limit source for Pi: advertise OpenCode Go model limits from its upstream model list, explicitly declare OMLX model limits in Nix, and have Pi consume the advertised values while retaining a 32,000-token maximum output cap. Keep the Bifrost executable out of the foundation role, sync the required Devenv Machines input with the root flake, and include the requested Drlight observability commit.

## Current behavior

- Bifrost already has a native `opencode-go` provider, but the Nix service module only supports custom `openai`, `anthropic`, and `vllm` upstreams.
- OpenCode Go's live `/v1/models` response includes limits under `limit.context` and `limit.output`. Bifrost's pinned OpenAI-compatible parser does not currently preserve those nested fields.
- The local OMLX model list does not advertise limits. The Pi discovery extension currently hardcodes `contextWindow: 128000` and does not set `maxTokens`.
- The live Bifrost management model-details endpoint is unavailable because dashboard authentication/setup is not configured. The design does not require enabling that endpoint or changing Bifrost's existing provider database.
- The foundation role had installed `bifrost-http` on every foundation-enabled host. The Bifrost service already references the package directly when enabled.
- Devenv does not install `bifrost-http` in its shell package list. Its `bifrost` input feeds the shared Machines overlay that builds the MegamanX service. Its locked revision was stale relative to root `flake.lock`.

## Design

1. Configure Bifrost's native OpenCode Go provider, reusing the existing Pi/Opnix-managed secret file and passing it to Bifrost through an environment-variable reference. Do not duplicate the credential or place the API key in Nix-generated JSON or the Nix store.
2. Extend the pinned Bifrost package's model-list handling to map OpenCode Go's nested context/output limits to Bifrost model metadata and include them in Bifrost's `/v1/models` response.
3. Add a Nix-declared, per-model metadata map to Bifrost configuration. Configure `omlx/qwen3.8-27b` with `context_length = 128000` and `max_output_tokens = 30720`; Bifrost merges these values into its model-list response only when the upstream has not provided them. Preserve Bifrost's existing SQLite provider/config state and default catalog source.
4. Update Pi discovery to use advertised model context limits, defaulting to 128000 only when missing. Set each Pi model's output limit to `min(advertised max_output_tokens, 32000)`; if Bifrost omits output metadata, use 32000. This keeps the cloud output cap at 32K and the OMLX cap at 30,720.
5. Keep `bifrost-http` out of the foundation system package list. The Bifrost LaunchDaemon still uses its package directly. Devenv does not install the binary in its shell package list, but its Bifrost input remains required by the shared Machines overlay. Sync that input's locked revision with the root flake.
6. Merge the single requested commit from `feat/drlight-sync-observability` (`8b4bc225`) into this work, preserving its Drlight metrics and storage observability changes.

## Non-goals

- Enabling Bifrost dashboard authentication or making management API calls.
- Changing oMLX's runtime context allocation, concurrency, memory guard, or cache settings.
- Applying or deploying the Nix configuration to MegamanX.
- Automatically inferring OMLX limits; OMLX metadata remains an explicit Bifrost-side Nix declaration.
- Removing Bifrost's Devenv input. The shared Machines build uses it to provide `pkgs.bifrost-http` for the MegamanX service. Align its lock with the root flake instead.

## Verification

- Go tests in the Bifrost source patch prove nested OpenCode Go limits survive parsing and are serialized in Bifrost's model-list output.
- Nix evaluation tests prove the native OpenCode Go provider, credential reference, and OMLX metadata are generated correctly without embedding a secret.
- A Node test exercises Pi's metadata mapper for nested Bifrost model responses, missing limits, and the 32K output cap.
- Run lint, focused checks, build checks, and the Bifrost package build. Do not deploy or switch the live host.
