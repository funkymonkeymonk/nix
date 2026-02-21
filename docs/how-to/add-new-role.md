# How to Add a New Role

This guide shows you how to create a new role for grouping packages and configurations.

## Steps

### 1. Define the Role in bundles.nix

Open `bundles.nix` and add your role under the `roles` attribute:

```nix
roles = {
  # ... existing roles ...

  my-role = {
    packages = with pkgs; [
      # Add packages for this role
      some-package
      another-package
    ];
    
    # Optional: Platform-specific packages
    darwinPackages = with pkgs; [
      # macOS-only packages
    ];
    
    linuxPackages = with pkgs; [
      # Linux-only packages
    ];
    
    # Optional: Homebrew casks (macOS only)
    homebrewCasks = [
      "some-app"
    ];
  };
}
```

### 2. Add Role-Specific Configuration (Optional)

If your role needs special configuration beyond packages:

```nix
my-role = {
  packages = [ ... ];
  
  # Enable specific modules
  enableAgentSkills = true;  # Example: enable agent skills
  
  # Add shell aliases
  shellAliases = {
    my-alias = "some-command";
  };
};
```

### 3. Validate

```bash
devenv tasks run test:full
```

### 4. Use the Role

Add the role to a machine configuration in `flake.nix`:

```nix
(mkBundleModule "aarch64-darwin" ["base" "developer" "my-role"])
```

### 5. Apply Changes

```bash
devenv tasks run switch
```

## Tips

- Keep roles focused on a single purpose
- Use platform-specific package lists for cross-platform compatibility
- Document what the role provides in this file or the README
