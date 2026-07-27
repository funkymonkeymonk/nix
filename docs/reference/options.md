---
title: "Configuration Options Reference"
description: "Complete reference for myConfig.* configuration options"
type: reference
audience: both
last-reviewed: 2026-07-27
---

# Configuration Options Reference

Options are defined in `modules/common/options.nix` under the `myConfig` namespace.

## User Configuration

### myConfig.users

List of users to configure on the system.

```nix
myConfig.users = [
  {
    name = "username";
    email = "user@example.com";
    fullName = "Full Name";
    isAdmin = true;
    sshIncludes = [];
  }
];
```

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `name` | string | required | Username for the user account |
| `email` | string | required | Email address |
| `fullName` | string | `""` | Full name of the user |
| `isAdmin` | bool | `true` | Whether user has admin privileges |
| `sshIncludes` | list of strings | `[]` | Additional SSH config files to include |

## Platform Detection

### myConfig.isDarwin

Read-only boolean indicating if the system is macOS.

```nix
config = mkIf config.myConfig.isDarwin {
  # macOS-only configuration
};
```

## Feature Toggles

### myConfig.agent-skills

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enable` | bool | `false` | AI agent skills management (auto-enabled by opencode/claude/pi roles) |

### myConfig.zellij

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enable` | bool | `false` | Enable zellij terminal multiplexer |

## 1Password Integration

### myConfig.onepassword

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enable` | bool | `true` | Enable 1Password integration |
| `enableGUI` | bool | `true` | Enable 1Password GUI application |
| `enableSSHAgent` | bool | `true` | Enable 1Password SSH agent |
| `enableGitSigning` | bool | `true` | Enable git commit signing |
| `signingKey` | string | `""` | SSH public key for git signing |
| `sudoPasswordRef` | string | `""` | 1Password reference for the sudo password used by `system:switch` |

## OpenCode Configuration

### myConfig.opencode

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enable` | bool | `false` | Enable OpenCode configuration |
| `model` | string or null | `null` | Default LLM model |
| `theme` | string | `"system"` | UI theme |
| `autoupdate` | bool | `true` | Enable automatic updates |
| `enableBrowserAgents` | bool | `false` | Enable browser automation agents |
| `disabledProviders` | list of strings | `[]` | Built-in providers to disable |

### myConfig.opencode.providers

Custom LLM provider configuration:

```nix
myConfig.opencode.providers = {
  my-provider = {
    npm = "@ai-sdk/openai-compatible";
    name = "My Provider";
    baseURL = "https://api.example.com";
    onePasswordItem = "op://vault/item/field";
    models = {
      "model-id" = { name = "Model Name"; };
    };
  };
};
```

### myConfig.opencode.commands

Custom slash commands:

```nix
myConfig.opencode.commands = {
  my-command = {
    template = "Do something with $ARGUMENTS";
    description = "Description shown in TUI";
    agent = null;      # Optional agent override
    subtask = null;    # Force subtask mode
    model = null;      # Override model
  };
};
```

### myConfig.opencode.extraMcpServers

Additional MCP servers:

```nix
myConfig.opencode.extraMcpServers = {
  my-server = {
    type = "remote";   # or "local"
    url = "https://...";
    command = [];      # For local servers
    enabled = true;
  };
};
```

## Claude Code Configuration

### myConfig.claude-code

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enable` | bool | `false` | Enable Claude Code configuration |
| `includeCoAuthoredBy` | bool | `false` | Include co-author trailers in commits |
| `extraSettings` | attrs | `{}` | Additional settings |
| `agents` | attrs | `{}` | Custom agents |
| `commands` | attrs | `{}` | Custom commands |
| `hooks` | attrs | `{}` | Custom hooks |

### myConfig.claude-code.mcpServers

MCP servers for Claude Code (same structure as OpenCode).

## LLM Client Configuration

Shared configuration for LLM client tools (OpenCode, Claude Code).

### myConfig.llmClient

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `serverHost` | string | `"127.0.0.1"` | Default LLM server host for client tools |
| `serverPort` | string | `"8080"` | Default LLM server port for client tools (bifrost gateway) |

### myConfig.llmClient.rtk

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enable` | bool | `false` | Enable RTK token optimization (integrates with OpenCode and Claude Code) |

## Skills Configuration

### myConfig.skills

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enabledRoles` | list of strings | `[]` | Enabled roles for skills filtering (set automatically by `modules/roles/default.nix`) |
| `skillsPath` | string | `".config/opencode/skills"` | Path relative to home directory where external skill placeholders are installed |
| `superpowersPath` | path or null | `null` | Path to the superpowers flake input (set automatically from flake inputs) |
| `externalInputs` | attrs of path | `{}` | External skill repository flake inputs (e.g. `vercel-skills = inputs.vercel-skills`) |

Internal and superpowers skills for opencode/claude-code are installed via
home-manager's native `programs.opencode.skills` / `programs.claude-code.skills`
options (see [Skills Reference](skills.md)), not `skillsPath`. `skillsPath`
only affects the external-skills placeholder mechanism in
`modules/home-manager/skills/install.nix`.

## NixOS-Specific Options

Defined in `modules/nixos/`:

### myConfig.desktop

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enable` | bool | `false` | Enable desktop environment (Plasma 6) |
| `autoLoginUser` | string or null | `null` | User for auto-login |

### myConfig.gaming

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enable` | bool | `false` | Enable gaming support (Steam, controllers) |

### myConfig.streaming

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enable` | bool | `false` | Enable Sunshine game streaming |

## Usage Example

```nix
# In flake.nix
"my-machine" = libraryLib.mkDarwinSystem {
  inherit inputs;
  hostname = "my-machine";
  extraSpecialArgs = {inherit mkUser;};
  modules = [
    ./library/archetypes/base-darwin.nix
    ./library/archetypes/developer-laptop-darwin.nix
    ./hosts/my-machine
  ];
};

# In hosts/my-machine/default.nix
{mkUser, ...}: {
  myConfig =
    mkUser "username" "email@example.com"
    // {
      roles.developer.enable = true;
      opencode.model = "claude-sonnet";
      onepassword.signingKey = "ssh-ed25519 ...";
    };
}
```

The `mkUser` helper sets common defaults (`users`, `onepassword.enable = true`,
default opencode/rtk config). Merge additional `myConfig` values on top in
your host file to override settings.
