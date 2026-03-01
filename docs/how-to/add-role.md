# Add a New Role

This guide shows you how to create a new role for grouping packages and configurations.

## Step 1: Open bundles.nix

Roles are defined in `bundles.nix` under the `roles` attribute.

## Step 2: Add Your Role

Add a new entry to the `roles` attribute set:

```nix
roles = {
  # ... existing roles ...

  my-role = {
    packages = with pkgs; [
      package1
      package2
    ];

    # Optional: Role-specific configuration
    config = {
      environment.variables = {
        MY_VAR = "value";
      };
    };

    # Optional: macOS Homebrew casks
    homebrewCasks = [
      "some-app"
    ];

    # Optional: Agent skills for this role
    agentSkills = [
      "debugging"
      "tdd"
    ];

    # Optional: Auto-enable agent-skills role
    enableAgentSkills = true;
  };
};
```

## Step 3: Use the Role

Reference your role in machine configurations:

```nix
"my-machine" = mkDarwinHost {
  target = ./targets/my-machine;
  user = mkUser "username" "email@example.com";
  roles = ["developer" "my-role"];  # Add your role here
};
```

## Step 4: Document the Role

Add your role to `docs/reference/roles.md`:

```markdown
### my-role

Brief description of the role's purpose.

**Packages:** package1, package2

**Homebrew Casks (macOS):** some-app

**Agent Skills:** debugging, tdd
```

## Platform-Specific Packages

To include packages only on certain platforms:

```nix
my-role = {
  # All platforms
  packages = with pkgs; [common-tool];

  # macOS only - use config.homebrew
  config.homebrew.casks = ["macos-app"];

  # For Linux-only packages, use conditionals in the packages list
  # or create separate darwinPackages/linuxPackages if needed
};
```

## Validation

After adding your role:

```bash
# Check syntax
devenv tasks run ci:quick

# Test a configuration using your role
nix build .#darwinConfigurations.my-machine.system --dry-run
```

> **See also:** [Roles Reference](../reference/roles.md) for existing role examples
