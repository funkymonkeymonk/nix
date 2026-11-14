# Remote Builder for Cross-Architecture Machine Builds

## Intent

Make `devenv tasks run machines:build --input machine=<name>` reliably use MegamanX for builds that cannot run on the current system, rather than silently falling back to a local build and failing with a platform mismatch.

## Goals and non-goals

- For a non-local `aarch64-darwin` target, build through MegamanX's `ssh-ng` remote Nix store and disallow local build jobs.
- Use the 1Password CLI (`op read`) to retrieve the existing builder private key from Zero's configured default vault only for that build operation, write it to a mode-`0600` temporary file, and remove it on exit. Do not require the Opnix runtime service or add a SecretSpec profile.
- Preserve the local build path for targets matching the current system.
- Fail with a clear diagnostic when a cross target is not `aarch64-darwin`, the key cannot be obtained, or the remote builder cannot build the derivation. Never report a local fallback as a successful cross build.
- Do not change machine activation, `machines:deploy`, `machines:plan`, or the installed Zero and MegamanX configurations.

## Approaches

1. Require the existing `/run/secrets/nix-remote-builder-megamanx` file and pass the configured builder explicitly. This avoids runtime 1Password access, but the file is absent in the current task environment and the cross build remains unusable there.
2. Use `op read` at task runtime to fetch the existing builder key from Zero's configured default vault, write it to a mode-`0600` temporary file, and route the build through MegamanX's `ssh-ng` remote store with local jobs disabled. **Selected:** this makes the named build flow self-contained while keeping the secret out of Nix expressions, derivations, logs, command arguments, and persistent files. The remote-store URI fits Devenv's single-token Nix option handling, unlike a whitespace-separated builder specification. Build outputs reside on MegamanX. SecretSpec could provide the same operation scoping, but would require an additional manifest profile and is unnecessary for this task.

## Design

`machine-ops.sh build` will compare the current Nix system with the named target system from catalog metadata. Equal systems keep the current `devenv build` command. A differing target is routed through MegamanX only when it is `aarch64-darwin`; other cross targets fail before a build starts because MegamanX advertises only `aarch64-darwin`.

For that remote path, the task will read the builder host, Nix system, SSH protocol/user, pinned public host key, private-key item reference, and default-vault name from Zero's canonical Nix configuration. It will assemble the 1Password URI and call `op read` without printing the value, write it to a protected temporary key file, URL-encode that path and host-key pin into an `ssh-ng://` remote-store URI, then invoke `devenv build` with `--nix-option store <uri>` and `--nix-option max-jobs 0`. Nix runs the build on MegamanX's remote daemon; build outputs reside in that remote store. The temporary key is removed on every exit path. It will not invoke the Opnix runtime service or resolve the key through Nix evaluation. The SSH URI uses the canonical Zero builder account, protocol, target system, and pinned public host key; local build jobs are disabled for the invocation.

## Tests

Extend the machine-operations shell test with mocked current/target systems, `op read`, and `devenv build`. Assert local builds do not fetch the secret; cross `aarch64-darwin` builds use the pinned MegamanX builder with local jobs disabled and remove the temporary key; unsupported cross targets fail before invoking the build; and failures do not leak key contents or leave the temporary key behind.
