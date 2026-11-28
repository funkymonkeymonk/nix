# Generic Bifrost Opnix Credential Creation

## Intent

Make Bifrost virtual-key creation reusable by name instead of hard-coding Zero, generate the missing setup-token secret, and align MegamanX's Nix references with the `Bifrost Admin` item the user moved into Opnix.

## Goals

- Add `secrets:create-bifrost-vk` with required `keyName` and `confirm=true` inputs.
- Accept a script argument `--key-name <name>` and create an Opnix `API Credential` titled `Bifrost <keyName> API Key`.
- Generate `sk-bf-` plus 32 cryptographically random bytes encoded as 64 lowercase hexadecimal characters; store it in the concealed `credential` field.
- Retain `secrets:create-bifrost-zero-vk` as a compatibility alias that passes `keyName=Zero`.
- Add `secrets:create-bifrost-setup-token`, generating 32 random bytes encoded as lowercase hex (no `sk-bf-` prefix) in the concealed `credential` field of `Bifrost Setup Token`.
- Update MegamanX's admin references to the moved Opnix Login item: `Bifrost Admin/username` and `Bifrost Admin/password`. Keep the setup-token reference unqualified as `Bifrost Setup Token/credential`.
- Resolve the Bifrost host's configured default vault (`MegamanX`), refuse active or archived duplicate titles, and never overwrite or rotate existing items.
- Preserve confirmation gates, private temporary files (directory 0700, files 0600), cleanup on every exit, and no-secret-output guarantees.
- Do not deploy or restart Bifrost from a credential-creation task.

## Non-goals

- Minting a key through Bifrost's management API. MegamanX already declares virtual keys in Nix and loads their values from Opnix; API-minted database state would have a separate owner and requires a running gateway.
- Copying the admin item across vaults. The user has moved it into Opnix; the Nix references should use that item through MegamanX's default vault.
- Rotating an existing virtual key or setup token.

## Approaches

1. **Nix-declarative Opnix credentials (selected):** parameterize the virtual-key creator, add a separate setup-token task because it has different semantics, and update the admin references to the moved Login item. This matches the existing Bifrost configuration and avoids a second API-managed source of truth.
2. **Mint a virtual key through Bifrost's management API:** rejected because the gateway is currently unavailable and the Nix configuration already declares the key.
3. **Use one generator for both virtual keys and setup tokens:** rejected because setup tokens are not `sk-bf-` virtual keys and should not share their prefix or validation semantics.

## Safety and operation

Each task requires explicit confirmation, refuses active or archived same-title items, and reports only non-secret metadata. Virtual keys use `sk-bf-` plus 64 lowercase hex characters; setup tokens use 64 lowercase hex characters without a prefix. Secret values are passed only through mode-0600 JSON templates in mode-0700 temporary directories, never through command arguments, environment variables, stdout, or logs. Opnix authentication must be available when tasks run. Task execution does not synchronize the service or activate Bifrost; deployment remains a separate reviewed operation.
