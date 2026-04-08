# Create Your First Role

In this tutorial, you'll create a custom role module that bundles packages and configuration together. By the end, you'll have a working role that can be enabled on any machine.

## What You'll Learn

- How role modules are structured
- How to define a new option in `options.nix`
- How to register and import the role
- How platform-specific config works

## Prerequisites

- Completed [Getting Started](getting-started.md) and [Add Your Machine](add-your-machine.md)
- Familiarity with the repo structure
- About 20 minutes

## Step 1: Pick a Role to Build

We'll create a `writing` role for documentation and technical writing. It will include:
- `vale` -- a prose linter
- `pandoc` -- a document converter
- `mdbook` -- a book builder from Markdown

## Step 2: Add the Enable Option

Open `modules/common/options.nix` and find the `myConfig.roles` section. You'll see existing roles like `developer`, `creative`, etc.

Add your new role alongside them:

```nix
writing = {
  enable = lib.mkEnableOption "writing tools for documentation and technical writing";
};
```

This creates a boolean option at `myConfig.roles.writing.enable` that defaults to `false`.

## Step 3: Create the Role Module

Create the file `modules/roles/writing.nix`:

```nix
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.myConfig.roles.writing;
in {
  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      vale
      pandoc
      mdbook
    ];
  };
}
```

The key pattern: `lib.mkIf cfg.enable { ... }` ensures the packages only install when the role is activated for a machine.

## Step 4: Import the Role

Open `modules/roles/default.nix` and add your module to the imports list:

```nix
imports = [
  # ... existing roles ...
  ./writing.nix
];
```

## Step 5: Validate

Run the checks to make sure everything evaluates:

```bash
devenv tasks run check:lint
devenv tasks run test:darwin-eval    # macOS
devenv tasks run test:nixos-eval     # NixOS
```

If you get an error like "option myConfig.roles.writing does not exist", double-check that you added the option in Step 2.

## Step 6: Enable the Role on Your Machine

In `flake.nix`, add `"writing"` to your machine's roles list:

```nix
"my-laptop" = mkDarwinHost {
  target = ./targets/my-laptop;
  user = mkUser "yourusername" "you@example.com";
  roles = ["developer" "desktop" "writing"];
};
```

## Step 7: Build and Apply

```bash
# macOS
nix build .#darwinConfigurations.my-laptop.system
./result/sw/bin/darwin-rebuild switch --flake .#my-laptop

# NixOS
sudo nixos-rebuild switch --flake .#my-laptop
```

## Step 8: Verify

```bash
vale --version
pandoc --version
mdbook --version
```

All three should be available.

## Going Further: Platform-Specific Packages

To add macOS-only Homebrew casks, guard them with a platform check:

```nix
config = lib.mkIf cfg.enable {
  environment.systemPackages = with pkgs; [
    vale
    pandoc
    mdbook
  ];

  # macOS Homebrew casks
  homebrew = lib.mkIf config.myConfig.isDarwin {
    casks = [
      "marked"    # Markdown previewer (macOS only)
    ];
  };
};
```

## What You've Learned

- Roles are NixOS modules gated by `lib.mkIf cfg.enable`
- Options go in `modules/common/options.nix`
- The module goes in `modules/roles/<name>.nix` and is imported in `default.nix`
- Platform checks use `config.myConfig.isDarwin`
- Always validate with lint + eval before applying

## What's Next

- **Add skills to your role**: See [Write Your First Skill](write-your-first-skill.md)
- **See all existing roles**: [Roles Reference](../reference/roles.md)
- **Add shell aliases**: Add an `environment.shellAliases` block inside the `mkIf`
- **Understand the module system**: [Architecture](../explanation/architecture.md)
