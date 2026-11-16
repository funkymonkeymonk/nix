# Pi Tailnet Bifrost Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make MegamanX's Bifrost provider available to every Pi instance configured for Tailscale, without changing existing default models or affecting non-tailnet Pi instances.

**Architecture:** Keep this behavior within Pi's role/model configuration. When `myConfig.tailscale.enable` is true, use `http://megamanx:8081/v1`; otherwise preserve the current `llmClient`-derived URL. Identify Bifrost discovery by the model's provider identifier rather than a hostname substring, and ensure Zero's customized Pi model set merges the role's Bifrost model.

**Tech Stack:** NixOS/nix-darwin Nix modules, Home Manager-generated Pi JSON, Nix eval/build tests, devenv tasks.

**Spec:** `docs/superpowers/specs/2026-11-14-pi-tailnet-bifrost-design.md`

## Global Constraints

- Only tailnet-enabled Pi configurations use `http://megamanx:8081/v1`.
- Non-tailnet Pi configurations retain their existing endpoint behavior.
- Do not change shared LLM endpoints used by OpenCode or Claude.
- Preserve existing default provider/model settings, including OpenCode Go.
- Do not change Tailscale enrollment, Bifrost's loopback binding, Serve exposure, or secrets.

## Review Focus

- A Pi instance outside the tailnet must not be redirected to MegamanX; assert the existing workstation model URL remains local.
- MegamanX itself must use the Tailscale-published endpoint and not its loopback listener; assert its resolved Pi Bifrost model URL.
- A tailnet host with a custom `myConfig.pi.models` set must still receive Bifrost without losing its custom provider; assert Zero retains OpenCode Go and includes Bifrost.
- Bifrost discovery must remain enabled when the base URL contains `megamanx` rather than `bifrost`; assert the extension is generated for a Bifrost provider model.
- Existing default provider/model selections must remain unchanged; assert Zero and MegamanX continue to select OpenCode Go as configured.

---

### Task 1: Pin the expected Pi gateway behavior in machine evaluation tests

**Files:**
- Modify: `tests/test-lydia-migration.nix`
- Modify: `tests/test-zero.nix`
- Test: existing `lydia-migration` and `zero-cloud-only-config` checks

**Interfaces:**
- Consumes: evaluated configurations `self.darwinConfigurations.MegamanX`, `self.nixosConfigurations.zero`, `self.darwinConfigurations.Lydia`, and `self.darwinConfigurations.wweaver`.
- Produces: regression assertions for the resolved Pi Bifrost model and current provider defaults.

- [ ] **Step 1: Add failing machine-evaluation assertions**

Assert MegamanX and Zero have `myConfig.pi.models.bifrost.baseUrl == "http://megamanx:8081/v1"`; Zero's Pi model set contains both `bifrost` and `opencode-go`; its `settings.defaultProvider` remains `opencode-go`; and MegamanX's existing default provider remains `opencode-go`. Assert the Bifrost discovery extension is generated for MegamanX at its new hostname URL. Assert Lydia and wweaver, which are not tailnet-enabled, retain a non-MegamanX model URL. Update Zero's cloud-only test to describe that OpenCode stays cloud-default while Pi has an optional remote Bifrost model, and stop asserting that the Pi configuration has no Qwen model.

- [ ] **Step 2: Commit the test-only changes before flake evaluation**

Stage the new plan/spec, then run `jj describe -m "test: cover tailnet Pi Bifrost routing"` followed by `jj new` to snapshot the test changes into the described revision and start a clean child. This ensures Nix flake evaluation reads the updated test files.

- [ ] **Step 3: Run focused checks and confirm RED**

Run: `devenv tasks run test:build-checks`
Expected: fail on the missing remote endpoint/model assertions before implementation.

### Task 2: Implement tailnet-aware Pi Bifrost configuration

**Files:**
- Modify: `modules/roles/pi.nix`
- Modify: `modules/home-manager/pi-coding-agent.nix`
- Modify: `machines/zero/default.nix`
- Test: `tests/test-lydia-migration.nix`, `tests/test-zero.nix`

**Interfaces:**
- Consumes: `config.myConfig.tailscale.enable` and the existing `llmClient.serverHost/serverPort` Pi role defaults.
- Produces: a `myConfig.pi.models.bifrost.baseUrl` selected from tailnet state, plus discovery based on `model.provider == "bifrost"`.

- [ ] **Step 1: Make the Pi role endpoint tailnet-aware**

In `modules/roles/pi.nix`, select `http://megamanx:8081/v1` when `config.myConfig.tailscale.enable` is true; otherwise retain `http://${host}:${port}/v1`. Keep this endpoint local to the Pi Bifrost model and leave `myConfig.llmClient` unchanged.

- [ ] **Step 2: Preserve Bifrost discovery for the remote hostname**

In `modules/home-manager/pi-coding-agent.nix`, identify Bifrost models by `model.provider == "bifrost"` instead of searching `baseUrl` for the string `bifrost`. This keeps discovery enabled when the endpoint is `megamanx`.

- [ ] **Step 3: Merge Zero's custom models with the Pi role default**

In `machines/zero/default.nix`, remove the force replacement on `myConfig.pi.models` and define only its `opencode-go` model override, allowing the role's `bifrost` model to remain. Preserve `defaultProvider = "opencode-go"` and all OpenCode Go/1Password settings.

- [ ] **Step 4: Commit the implementation before flake evaluation**

Stage the modified Nix modules and Zero configuration, then run `jj describe -m "feat: route tailnet Pi through MegamanX Bifrost"` followed by `jj new` to snapshot those changes into the described revision and start a clean child.

- [ ] **Step 5: Run focused checks and confirm GREEN**

Run: `devenv tasks run test:build-checks`
Expected: pass, including the machine-evaluation and Zero-specific regressions.

### Task 3: Validate, format, commit, and prepare the PR

**Files:**
- Review: all files changed above plus the approved spec and this plan.

- [ ] **Step 1: Run required lint and full tests**

Run: `devenv tasks run check:lint`
Expected: pass with no formatting or dead-code issues.

Run: `devenv tasks run test:all`
Expected: pass for the supported platform tests/evaluation checks.

- [ ] **Step 2: Review the final diff and status**

Run: `jj diff` and `jj status` from the feature workspace.
Expected: only the design/plan and approved Pi Bifrost config/tests are changed.

- [ ] **Step 3: Publish the feature bookmark**

Create a feature bookmark at the final commit and publish with `jj git push`.

- [ ] **Step 4: Create a pull request**

Use `gh pr create` with a concise summary, test results, and a link to the design/plan. If GitHub authentication or repository permissions prevent PR creation, report the exact blocker and leave the published branch ready for a PR.
