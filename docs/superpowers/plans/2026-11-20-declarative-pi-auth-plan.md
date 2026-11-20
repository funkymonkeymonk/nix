# Declarative Pi auth.json Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Manage MegamanX's Pi `auth.json` declaratively while keeping the OpenCode Go key backed by an OpNix-materialized file.

**Architecture:** Add `auth.json` to the existing Home Manager-generated Pi files with an `opencode-go` credential whose key is the Pi-supported `!cat ~/.pi/agent/secrets/opencode-go-apikey` command. Remove the activation script that currently merges this entry into a mutable file; OpNix continues to materialize the secret file itself.

**Tech Stack:** Nix, Home Manager, Pi coding agent, OpNix.

**Spec:** The machine's `~/.pi/agent/auth.json` contains only `opencode-go`, so replacing it declaratively will not discard unmanaged credentials.

## Global Constraints

- Do not put the resolved API key in the Nix store.
- Keep the OpNix secret reference and materialized path unchanged.
- Preserve Pi's `!cat` runtime credential resolution.
- Remove the obsolete activation job and its merge-preservation test.

## Review Focus

- The generated file must contain only the expected provider and runtime command.
- The secret value must remain outside the Nix store.
- The activation attribute `piOpenCodeGoAuth` must no longer be generated.
- Existing Pi configuration files must continue to be generated.

---

### Task 1: Declarative Pi auth file

**Files:**
- Modify: `modules/home-manager/pi-coding-agent.nix`
- Modify: `tests/test-pi.nix`

- [ ] **Step 1: Write the failing test**

Extend the Pi module test to assert that the generated `home.file` contains `.pi/agent/auth.json` with an `opencode-go` API-key entry whose key is exactly `!cat ~/.pi/agent/secrets/opencode-go-apikey`, and assert that the module text no longer defines `piOpenCodeGoAuth`.

- [ ] **Step 2: Run the focused test and verify it fails**

Run the Pi test check and confirm it fails because `auth.json` is not currently in `home.file` and the activation job still exists.

- [ ] **Step 3: Implement the declarative file**

Add the conditional `.pi/agent/auth.json` entry to `allFiles`, using JSON generated from the `opencodeGoOnePasswordItem` condition and the `!cat` command. Remove `home.activation.piOpenCodeGoAuth`.

- [ ] **Step 4: Run focused and repository checks**

Run the Pi check, `devenv tasks run check:lint`, and `devenv tasks run test:build-checks`.

- [ ] **Step 5: Describe the change with jj**

Use `jj describe -m "feat: manage pi auth declaratively"` and then `jj new`.
