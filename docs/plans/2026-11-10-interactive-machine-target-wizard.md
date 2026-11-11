# Interactive Machine Target Wizard Implementation Plan

> **Note:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add an interactive `machines:new` devenv task that scaffolds registered Darwin or NixOS targets for supported platforms, with archetype and role selection.

**Architecture:** A Gum-driven shell script gathers and validates input, then atomically writes a machine module and a per-machine catalog entry. A small Nix manifest supplies platform-compatible archetypes and roles, while `catalog.nix` loads generated catalog entries and checks collisions. The task only scaffolds and can optionally evaluate the target; it never installs, deploys, switches, or configures disks.

**Tech Stack:** Nix modules and flake catalog, devenv tasks, Bash, Gum, Nix evaluation checks, shell test fixtures.

---

### Task 1: Specify the wizard's option manifest and test its invariants

**Files:**
- Create: `library/machines/wizard-options.nix`
- Create: `tests/test-machine-wizard-options.nix`
- Modify: `tests/default.nix`

**Step 1: Write failing manifest tests**

Add tests asserting:
- Supported platforms are exactly `aarch64-darwin`, `x86_64-linux`, and `aarch64-linux`.
- Darwin archetypes are only listed for Darwin; NixOS archetypes are only listed for Linux systems they support.
- Every referenced archetype path exists.
- Every listed role name appears in the `myConfig.roles` definitions imported by the common module stack for that OS.
- Archetypes and roles are separately represented so selection cannot confuse a profile with an additional role.

Export a new check in `tests/default.nix` named `machine-wizard-options`.

**Step 2: Run the check to confirm RED**

Run:

```bash
CURRENT_SYSTEM=$(nix eval --impure --expr 'builtins.currentSystem' --raw)
nix build ".#checks.${CURRENT_SYSTEM}.machine-wizard-options" --no-link --impure
```

Expected: evaluation fails because the manifest and test do not exist yet.

**Step 3: Add the minimal manifest and check**

Create a Nix attrset keyed by supported platform. Each platform record contains labeled archetype choices (module paths) and the available role names. Include only independently usable archetypes. For shared profiles such as `type-server`, include the profile only on platforms where the module and its package/service composition are valid.

Implement test assertions against the manifest and actual paths/options. Do not discover every `.nix` file in `library/archetypes/`; base and capability modules are not all standalone profiles.

**Step 4: Run the check to confirm GREEN**

Run the build command above and expect it to complete successfully.

**Step 5: Commit**

```bash
jj describe -m "feat: define machine wizard bundle choices"
```

---

### Task 2: Test the interactive generator contract before implementation

**Files:**
- Create: `tests/test-machine-scaffold.sh`
- Create: `tests/test-machine-scaffold.nix`
- Modify: `tests/default.nix`

**Step 1: Write a shell test with a fake Gum executable**

The test must create a temporary fixture repository containing a minimal catalog and template directories. Put a fake `gum` executable at the front of `PATH`; it reads a queued response file and logs arguments so the test can drive each prompt deterministically without a real TTY.

Cover at least:
- A successful Darwin target with an archetype, multiple roles, identity, hostname, state version, and secret profile.
- A successful NixOS target for `aarch64-linux` and one for `x86_64-linux`, with an explicit state version and no disk config.
- A successful Darwin target for `aarch64-darwin`.
- Cancellation at a prompt and declining the final confirmation leave no generated files.
- Missing required fields, invalid names, unsupported bundle choices, and duplicate catalog/directory names fail before writes.
- Existing files are never overwritten.
- Generated summary includes the selected platform, archetype, roles, user identity, and SecretSpec profile.
- The script never invokes install, deploy, apply, switch, or disk commands.

Set `MACHINE_SCAFFOLD_ROOT` to the fixture and `GUM_BIN` to the fake executable so the script can run against a temporary tree. Export the script path through `MACHINE_SCAFFOLD_SCRIPT` for the test wrapper.

**Step 2: Verify RED**

Run:

```bash
bash tests/test-machine-scaffold.sh
```

Expected: fail because `scripts/machine-scaffold.sh` does not exist.

**Step 3: Add a Nix test wrapper**

Follow `tests/test-machine-ops.nix`: use a `pkgs.runCommand` derivation with Bash, coreutils, grep, and any other needed native tools to run `tests/test-machine-scaffold.sh` against `scripts/machine-scaffold.sh`. Export it in `tests/default.nix` as `machine-scaffold`.

**Step 4: Verify the wrapper is RED too**

Run:

```bash
CURRENT_SYSTEM=$(nix eval --impure --expr 'builtins.currentSystem' --raw)
nix build ".#checks.${CURRENT_SYSTEM}.machine-scaffold" --no-link --impure
```

Expected: fail on the missing script, not on test syntax.

**Step 5: Commit**

```bash
jj describe -m "test: define machine scaffold wizard behavior"
```

---

### Task 3: Implement the Gum prompt flow and atomic file generation

**Files:**
- Create: `scripts/machine-scaffold.sh`
- Modify: `tests/test-machine-scaffold.sh`

**Step 1: Implement root and interactivity checks**

Require an interactive stdin/stdout for real invocation. Allow the test-only `MACHINE_SCAFFOLD_ROOT` and `GUM_BIN` overrides. Check the expected catalog and option manifest exist before prompting. Use a cleanup trap for temporary output paths.

**Step 2: Implement platform-filtered questions**

Prompt in this order: target kind; compatible system; name/hostname; full name, account name, email; state version (Darwin defaults to `4`, NixOS requires a prompt); SecretSpec profile; compatible archetype; additional roles; final summary and confirmation. Use `gum choose` for single selections, `gum filter`/`gum choose --no-limit` or an equivalently tested multiselect for roles, `gum input` for text, and `gum confirm` before any output is written.

Check Gum return codes carefully. A cancel action should exit successfully without writing files; invalid or empty required inputs should show a clear message and re-prompt or exit before writes.

**Step 3: Render Nix safely**

Use a single escaping helper for interpolating prompted strings into Nix string literals. Validate machine names and hostnames against conservative patterns before rendering. Render role enables from the manifest allowlist, never from arbitrary shell input. The generated module imports exactly the selected archetype and sets only selected additional roles plus machine-specific state and identity settings. The generated catalog entry uses the correct `darwinMachine` or `nixosMachine` constructor, catalog platform/hostname fields, profile, module path, and user overrides. Preserve the prompted full name rather than relying on the existing `mkUser` default.

**Step 4: Make writes atomic and non-destructive**

Render both files to a temporary directory under the repository, verify destination paths remain absent, then move the completed directory and catalog entry into place. If either final move fails, remove any newly created companion output. Do not modify existing files or the main `catalog.nix` directly.

**Step 5: Run the shell contract tests and confirm GREEN**

Run:

```bash
bash tests/test-machine-scaffold.sh
```

Expected: all prompt, validation, cancellation, output, duplicate, and atomicity assertions pass.

**Step 6: Refactor only while tests remain green**

Extract small shell helpers only where they clarify input validation, Nix escaping, or file rendering. Rerun `bash tests/test-machine-scaffold.sh` after each refactor.

**Step 7: Commit**

```bash
jj describe -m "feat: scaffold machine targets interactively"
```

---

### Task 4: Load generated catalog entries and reject collisions

**Files:**
- Modify: `library/machines/catalog.nix`
- Create: `library/machines/generated/.keep` only if needed for the directory convention (prefer no placeholder if the loader handles an absent directory)
- Create: `tests/test-machine-generated-catalog.nix`
- Modify: `tests/default.nix`
- Modify: `tests/test-machines-inventory.nix`

**Step 1: Write failing catalog loader tests**

Assert that:
- The existing catalog is unchanged when the generated-entry directory is empty or absent.
- A generated Nix entry using the standard constructor is merged and projected to the correct platform configuration.
- A generated entry colliding with a hand-maintained catalog name fails with an error naming the duplicate machine.
- Invalid generated files or unsupported entry shapes fail clearly.

Use temporary fixtures or a factored loader helper so tests do not edit the real catalog. Export a focused check named `machine-generated-catalog`.

**Step 2: Verify RED**

Run:

```bash
CURRENT_SYSTEM=$(nix eval --impure --expr 'builtins.currentSystem' --raw)
nix build ".#checks.${CURRENT_SYSTEM}.machine-generated-catalog" --no-link --impure
```

Expected: failure because generated catalog loading is not implemented.

**Step 3: Implement a separate generated catalog loader**

Add a focused helper under `library/machines/` that reads only `.nix` files from `library/machines/generated/`, imports each with the constructors and `mkUser` it needs, and returns named machine records. Merge those records with the existing hand-maintained catalog in `catalog.nix`. Detect collisions explicitly before merging; do not let Nix's `//` silently replace an existing machine.

Make absent generated-entry directories equivalent to an empty attrset so a clean checkout continues to evaluate before the first wizard run.

**Step 4: Verify GREEN and inventory parity**

Run:

```bash
CURRENT_SYSTEM=$(nix eval --impure --expr 'builtins.currentSystem' --raw)
nix build ".#checks.${CURRENT_SYSTEM}.machine-generated-catalog" ".#checks.${CURRENT_SYSTEM}.machines-inventory" --no-link --impure
```

Expected: both checks pass; the standard catalog and Machines/flake projections contain identical names.

**Step 5: Commit**

```bash
jj describe -m "feat: load generated machine catalog entries"
```

---

### Task 5: Integrate the devenv task and bundle manifest

**Files:**
- Modify: `devenv.nix`
- Modify: `library/machines/wizard-options.nix`
- Modify: `tests/test-machine-scaffold.nix`
- Modify: `tests/test-machine-wizard-options.nix`

**Step 1: Add integration assertions first**

Extend the Nix wrapper tests to assert `machines:new` is exposed, Gum is present in the devenv package set, the task delegates to the script from the repo root, and it does not run other machine operations implicitly. Add assertions that manifest entries used by each supported system map to existing modules and valid roles.

Run the focused checks and confirm RED for the missing task/package integration.

**Step 2: Add Gum and the thin task**

Add `pkgs.gum` to `devenv.nix`'s repository tooling packages. Add a `machines:new` task adjacent to `machines:info`/`machines:chart` which executes the scaffold script and lets errors propagate. Do not add a target input that defaults to an existing host.

**Step 3: Finalize menu metadata**

Ensure all compatible standalone archetypes and roles are listed for the three supported systems. Include human-readable labels and actual import paths. Do not include base or capability modules as standalone archetypes. Do not add disk-layout options.

**Step 4: Verify GREEN**

Run:

```bash
CURRENT_SYSTEM=$(nix eval --impure --expr 'builtins.currentSystem' --raw)
nix build ".#checks.${CURRENT_SYSTEM}.machine-wizard-options" ".#checks.${CURRENT_SYSTEM}.machine-scaffold" --no-link --impure
```

Expected: both focused checks pass and devenv evaluation exposes `machines:new`.

**Step 5: Commit**

```bash
jj describe -m "feat: expose machine creation devenv task"
```

---

### Task 6: Add optional target evaluation and user documentation

**Files:**
- Modify: `scripts/machine-scaffold.sh`
- Modify: `tests/test-machine-scaffold.sh`
- Modify: `docs/reference/tasks.md`
- Modify: `docs/tutorials/setup-your-mac.md`
- Create or modify: `docs/how-to/create-machine-target.md`
- Modify: `docs/reference/index.md` if the new guide needs linking

**Step 1: Write failing tests for optional evaluation**

Use a fake `nix` executable to assert the wizard offers evaluation only after successful generation, selects the exact `nixosConfigurations` or `darwinConfigurations` name, and does not invoke `nix build`, `darwin-rebuild`, `nixos-rebuild`, or deployment tasks. Assert evaluation failure preserves diagnostics and leaves the generated scaffold intact.

Run the shell test and confirm expected failures before adding the implementation.

**Step 2: Implement the optional evaluation**

After files are generated, offer an explicit evaluation prompt. If accepted, evaluate the selected configuration's `system.build.toplevel.drvPath` using `nix eval` (not `nix build`). Preserve output and return a useful nonzero status on failure without deleting generated files. If declined, print the exact next-step commands.

**Step 3: Document the task**

Document `devenv tasks run machines:new`, supported systems, archetype/role distinction, the fields requested, generated file locations, the optional eval, and the fact that NixOS disk/facter setup, build, installation, deployment, and switching are intentionally not performed.

Update the Mac setup tutorial to point users to this wizard instead of instructing every new Mac owner to edit the catalog by hand. Keep any manual-edit guidance only where it remains useful for advanced/custom configurations.

**Step 4: Verify focused behavior and docs**

Run:

```bash
bash tests/test-machine-scaffold.sh
devenv tasks run docs:validate
```

Expected: shell assertions pass and docs validation succeeds.

**Step 5: Commit**

```bash
jj describe -m "docs: explain interactive machine target setup"
```

---

### Task 7: Run repository validation and review the complete diff

**Files:** all files modified by Tasks 1–6.

**Step 1: Run focused and required checks**

```bash
bash tests/test-machine-scaffold.sh
devenv tasks run check:lint
devenv tasks run test:eval
devenv tasks run test:build-checks
```

Expected: all commands exit successfully. If a platform-specific test cannot run on the current platform, report that clearly and run the closest supported evaluation check.

**Step 2: Inspect the final diff and target safety behavior**

Use `jj diff` and review:
- New configurations are loaded only through generated catalog entries.
- Existing catalog names and machine files are unchanged.
- No secret values are generated or written.
- No disk, installation, deployment, or switch operation is invoked.
- Generated templates are formatted with Alejandra and shellchecked.

**Step 3: Run any failed check again after fixes**

For each correction, rerun its focused check, then rerun lint and the relevant evaluation/build-check suite.

**Step 4: Final commit**

```bash
jj describe -m "feat: add interactive machine target wizard"
```
