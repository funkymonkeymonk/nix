# How to Add a New Machine

This guide shows you how to add a new machine to this Nix configuration.

## Steps

### 1. Create the Target Configuration

Create a new directory and configuration file:

```bash
mkdir -p targets/my-machine
```

Create `targets/my-machine/default.nix` based on your platform:

**For macOS (Darwin):**
```nix
{ config, lib, pkgs, ... }:

{
  networking.hostName = "my-machine";
  
  # Machine-specific settings go here
}
```

**For Linux (NixOS):**
```nix
{ config, lib, pkgs, ... }:

{
  networking.hostName = "my-machine";
  
  # Machine-specific settings go here
}
```

### 2. Add to flake.nix

Add your machine to the appropriate configuration section in `flake.nix`:

**For macOS:**
```nix
darwinConfigurations."my-machine" = nix-darwin.lib.darwinSystem {
  system = "aarch64-darwin";  # or "x86_64-darwin"
  modules = commonModules ++ [
    ./targets/my-machine
    (mkUser "yourusername")
    (mkNixHomebrew "yourusername")
    (mkBundleModule "aarch64-darwin" ["base" "developer"])  # Choose your roles
  ];
};
```

**For NixOS:**
```nix
nixosConfigurations."my-machine" = nixpkgs.lib.nixosSystem {
  system = "x86_64-linux";
  modules = commonModules ++ [
    ./targets/my-machine
    (mkUser "yourusername")
    (mkBundleModule "x86_64-linux" ["base" "developer"])  # Choose your roles
  ];
};
```

### 3. Validate the Configuration

```bash
devenv tasks run test:full
```

### 4. Apply to the Machine

On the new machine:

```bash
devenv tasks run switch
```

## Choosing Roles

Select roles based on what you need:

| Role | Use Case |
|------|----------|
| `base` | Essential tools (always include) |
| `developer` | Development environment |
| `creative` | Media tools |
| `workstation` | Work tools |
| `gaming` | Gaming tools |

> For the complete list, see [Roles Reference](../reference/roles.md).
