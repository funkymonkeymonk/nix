---
title: "Create a Machine Target"
description: "Use the interactive wizard to scaffold a registered Darwin or NixOS machine target"
type: how-to
audience: both
last-reviewed: 2026-11-10
---

# Create a Machine Target

Use the interactive shell command to create a machine module and register a new Darwin or NixOS target in the machine catalog. It runs directly in your terminal so Gum can receive input.

## Create the target

1. Run the interactive shell command from the repository root. This launches Gum directly in your terminal so it can receive keyboard input:

   ```bash
   devenv shell machine-new
   ```

   You can also enter `devenv shell` first and then run `machine-new`.

2. Choose the target kind and a compatible system. The supported choices are:

   | Target kind | Supported systems |
   |-------------|-------------------|
   | Darwin | `aarch64-darwin` |
   | NixOS | `x86_64-linux`, `aarch64-linux` |

3. Answer the prompts. The wizard asks for the machine output name, hostname, primary user's full name, account name and email, a SecretSpec profile, a compatible archetype, and any additional roles. NixOS also asks for an explicit state version; Darwin uses state version `4`.

   An **archetype** is the base configuration bundle for the target. **Roles** are separate, optional capabilities layered on top of that bundle. Select roles in addition to—not instead of—the archetype. The menu limits archetypes and roles to the choices supported for the selected system.

4. Review the summary and confirm creation. The wizard writes:

   - `machines/<name>/default.nix` — the machine module, selected archetype, user identity, state version, and selected role enables.
   - `library/machines/generated/<name>.nix` — the catalog record that registers the target.

   Review both generated files before continuing. The wizard does not overwrite an existing target.

5. Choose whether to evaluate the new configuration. If accepted, the wizard runs only `nix eval --raw` for the selected `nixosConfigurations.<name>` or `darwinConfigurations.<name>` configuration's `config.system.build.toplevel.drvPath`. This checks evaluation and prints the derivation path; it does not build it. If evaluation fails, Nix's diagnostics are shown and the generated files are kept. If the generated files are not visible to the flake because they are untracked, review them and make them visible to Nix through your normal version-control workflow before retrying; the wizard does not stage files.

   If you decline evaluation, the wizard prints the exact evaluation command to run later.

## Complete platform-specific setup

For NixOS, configure the machine's hardware and facter inputs and choose a disk layout manually before attempting to build or install it. The wizard does not collect a hardware report or create disk configuration.

The wizard only creates configuration. It does not run `nix build`, installation, deployment, or switching commands. After the generated files and any required platform-specific configuration are ready, validate and build the intended target using the repository's normal workflow.

For a custom target that does not fit the wizard's supported archetypes or prompts, an advanced configuration can still be assembled manually using the existing machine modules and catalog records as examples.
