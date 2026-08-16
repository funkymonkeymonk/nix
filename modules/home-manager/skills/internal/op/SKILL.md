---
name: op
description: Work with 1Password secrets via the op CLI. Use when the user wants to discover vaults, list items, inject secret references, or run commands with secrets. Handles biometric auth popups and never exposes secret values to the LLM.
---

# 1Password (op)

Use this skill when the user asks to work with 1Password secrets, credentials, passwords, API keys, or the `op` CLI.

## Authentication Workflow

The 1Password CLI (`op`) requires biometric or system authorization when using desktop app integration. **The human must authorize a popup on their device.** The pi-plugin-op extension handles this automatically by pausing and asking the human to authorize before running `op` commands.

If an `op` command fails with a lock or authorization error:
1. Inform the human that 1Password needs authorization.
2. The human should check for a system auth or biometric popup (Touch ID, Windows Hello, etc.).
3. Use the `/op:signin` command or wait for the human to confirm they have authorized it.

## Security Model: Values Never Exposed to the LLM

**Secret values are never exposed to the LLM context.** The plugin only works with secret *references* (`op://...` URIs), not the actual values.

- `op_vault_list`, `op_item_list`, `op_item_get` — discover metadata only (names, IDs, field labels, types). Field values are redacted before reaching the LLM.
- `op_inject` — saves only the `op://` reference string, not the value.
- `op_env` — shows `export VAR="op://..."` statements with references only.

To *use* a secret in a command, pass the reference to `op run` via bash:

```bash
export DB_PASSWORD="op://prod/db/password"
op run -- npm start
```

`op run` resolves the reference in a subprocess. The secret value never enters the LLM context.

## Secret References

1Password uses secret references in the format:

```
op://<vault>/<item>/<field>
```

For items with sections, the format is:

```
op://<vault>/<item>/<section>/<field>
```

You can discover vaults with `op_vault_list`, items with `op_item_list`, and fields with `op_item_get`.

## Best Practices

- **Never ask the user to reveal a secret value.** Use references and `op run` instead.
- **Inject for reuse**: Use `op_inject` to save commonly used secret references by name. They persist in the session and can be viewed with `op_env`.
- **Use `op run`**: To run commands with secrets as environment variables, prefix with `op run --`.
- **Check auth before bulk operations**: When running multiple `op` commands, the first one will trigger the auth prompt if needed. Subsequent commands in the same turn should reuse the established session.
