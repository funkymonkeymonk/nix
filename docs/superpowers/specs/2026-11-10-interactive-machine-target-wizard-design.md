# Interactive Machine Target Wizard Design

**Status:** Approved in chat; awaiting spec review  
**Date:** 2026-11-10

## Goal

Add an interactive devenv shell command that guides an operator through creating a new machine target in this repository. The wizard must support Darwin and NixOS, including the repository's supported platforms `aarch64-darwin`, `x86_64-linux`, and `aarch64-linux`. It must let the operator select one compatible archetype and additional roles, then create a scaffold that is registered in the machine catalog. Use a shell command rather than a devenv task because Gum needs the terminal's interactive input/output.

The wizard scaffolds configuration only. It does not install, deploy, switch, partition disks, or collect hardware reports.

## User flow

Run:

```sh
devenv shell machine-new
```

The interactive script checks that it is running in a TTY and that the repository is at the expected root. Run it with `devenv shell machine-new` or from an already active devenv shell; do not invoke it through the task runner because the task runner may not preserve the terminal. It then prompts in this order:

1. Target kind: Darwin or NixOS.
2. Platform/architecture filtered by target kind: Darwin offers `aarch64-darwin`; NixOS offers `x86_64-linux` and `aarch64-linux`.
3. Machine output name and hostname (hostname defaults to the output name).
4. Primary user's full name, account name, and email for the generated user configuration. Do not rely on `mkUser`'s current hard-coded full name.
5. State version: Darwin uses the repo's current Darwin state version (4); NixOS prompts for an explicit state version because this value affects persistent data and must not be guessed.
6. A configured SecretSpec profile. The wizard stores only the profile name, never secret values or credentials.
7. One compatible archetype/profile.
8. Zero or more additional roles, selected separately from the archetype.
9. A summary and explicit confirmation before any files are written.
10. An optional target-specific Nix evaluation after generation. This evaluates configuration only; it does not build or activate the system.

NixOS disk layout, disko settings, hardware discovery, and facter reports remain manual follow-up work. The wizard explains this in the summary and completion message. Canceling at any prompt or declining the final confirmation leaves the repository unchanged.

## Bundle selection data

Add a small checked-in wizard-options manifest for the supported platforms. It maps each platform to compatible archetypes and the available additional roles, with labels for prompt display and module paths for generated configuration. This provides a clear compatibility boundary rather than discovering every file under `library/archetypes/` (which also contains foundational or capability modules that are not standalone machine profiles).

The manifest must be kept aligned with actual archetype files and role options. Automated tests will verify referenced archetypes exist and role names remain valid. A role can only be selected once; the selected archetype and selected roles remain distinct in the generated target.

## Generated files and catalog integration

The wizard creates:

- `machines/<name>/default.nix` for machine-specific configuration, including the selected archetype import, selected role enables, and platform-appropriate state-version settings.
- `library/machines/generated/<name>.nix` for the machine's catalog record, including kind, platform, hostname, secret profile, module path, and user overrides. Generated user data must preserve the prompted full name rather than inherit the current helper's hard-coded value.

Extend `library/machines/catalog.nix` to load the generated catalog records and merge them with the existing hand-maintained records. The loader must fail clearly if a generated record collides with an existing machine name. Generated records must use the same `darwinMachine`/`nixosMachine` constructors and metadata shape as existing catalog records.

Generation must validate names before writing, reject names that already exist in either the catalog or target directories, and stage both outputs in temporary paths before atomically moving them into place. If generation fails or is canceled, it must not leave a partial machine directory or catalog entry. The wizard must not overwrite existing files.

## Implementation components

- Add `scripts.machine-new` to `devenv.nix` as a shell command that directly invokes the interactive scaffold script; do not register it as a devenv task.
- Add `gum` to the devenv environment so the shell command has a reproducible interactive dependency, following the repository's existing gum-based installer convention.
- Add a shell script under `scripts/` to drive prompts, validate input, render output from templates, stage files, and optionally evaluate the generated target.
- Add the wizard-options manifest and the catalog loader for generated entries.
- Add automated shell/Nix tests and document usage and NixOS limitations.

## Failure handling and safety

- Non-interactive invocation fails with an actionable message; it does not silently select defaults.
- Invalid machine names, empty required values, unsupported platform/archetype combinations, unavailable roles, and duplicate names are rejected before writing.
- Cancelation at any prompt is successful and leaves no output behind.
- The summary displays every value that will be written; no files are created until confirmation.
- The optional evaluation reports the exact target and preserves evaluator diagnostics. Failure does not remove or rewrite generated files; the completion message points to the generated paths for correction.
- The shell command never calls `machines:install`, `machines:deploy`, `machines:apply`, `system:switch`, or any disk operation.

## Testing

Use test-driven development. Add tests before implementation and verify expected RED failures.

1. A shell test runs the wizard with a fake `gum` executable and temporary repository fixture. It checks the supported platform choices, archetype/role selection flow, output values, cancellation, invalid/duplicate names, declined confirmation, and no-partial-write behavior.
2. Nix evaluation tests exercise loading generated catalog entries and confirm duplicate names fail with a useful message.
3. Manifest tests assert every listed archetype path exists and listed roles are defined for the appropriate platform.
4. Run `devenv tasks run check:lint`, the focused new tests, `devenv tasks run test:eval`, and `devenv tasks run test:build-checks` as feasible.

## Out of scope

- Selecting or generating NixOS disk layouts, disko modules, or hardware/facter inputs.
- Building, installing, deploying, switching, or changing any live machine.
- Editing 1Password items or managing secret values.
- Modifying existing machine profiles as a side effect of creating a new one.
