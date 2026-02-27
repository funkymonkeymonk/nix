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

### myConfig.development

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enable` | bool | `false` | Enable development tools |

### myConfig.agent-skills

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enable` | bool | `false` | Enable agent skills management |

### myConfig.zellij

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enable` | bool | `false` | Enable zellij terminal multiplexer |

## 1Password Integration

### myConfig.onepassword

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enable` | bool | `false` | Enable 1Password integration |
| `enableGUI` | bool | `true` | Enable 1Password GUI application |
| `enableSSHAgent` | bool | `true` | Enable 1Password SSH agent |
| `enableGitSigning` | bool | `true` | Enable git commit signing |
| `signingKey` | string | `""` | SSH public key for git signing |

## OpenCode Configuration

### myConfig.opencode

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enable` | bool | `false` | Enable OpenCode configuration |
| `model` | string or null | `null` | Default LLM model |
| `theme` | string | `"opencode"` | UI theme |
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
| `rtk.enable` | bool | `false` | Enable RTK token optimization |

### myConfig.claude-code.mcpServers

MCP servers for Claude Code (same structure as OpenCode).

## Skills Configuration

### myConfig.skills

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enabledRoles` | list of strings | `[]` | Enabled roles (set automatically) |
| `skillsPath` | string | `".config/opencode/skills"` | Skills installation path |
| `superpowersPath` | path or null | `null` | Path to superpowers input |

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
"my-machine" = mkDarwinHost {
  target = ./targets/my-machine;
  user = mkUser "username" "email@example.com";
  roles = ["developer"];
  extraConfig = {
    opencode.model = "claude-sonnet";
    onepassword.signingKey = "ssh-ed25519 ...";
  };
};
```

The `mkUser` helper sets common defaults. Use `extraConfig` to override settings.
