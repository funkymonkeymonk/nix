# Devenv Git Hooks

Pre-commit hooks via [git-hooks.nix](https://github.com/cachix/git-hooks.nix).

## Quick Setup

```nix
{ pkgs, ... }:

{
  git-hooks.hooks = {
    # Linters
    shellcheck.enable = true;
    eslint.enable = true;
    
    # Formatters
    black.enable = true;
    prettier.enable = true;
    nixfmt.enable = true;
    
    # Other
    markdownlint.enable = true;
  };
}
```

```bash
$ devenv shell
pre-commit installed at .git/hooks/pre-commit
```

Hooks run automatically on `git commit`.

## Available Hooks

Common hooks (full list at https://devenv.sh/reference/options/#git-hooks):

| Hook | Language | Purpose |
|------|----------|---------|
| `shellcheck` | Shell | Lint shell scripts |
| `black` | Python | Format Python |
| `ruff` | Python | Lint/format Python |
| `eslint` | JS/TS | Lint JavaScript |
| `prettier` | Various | Format code |
| `nixfmt` | Nix | Format Nix |
| `rustfmt` | Rust | Format Rust |
| `clippy` | Rust | Lint Rust |
| `gofmt` | Go | Format Go |
| `ormolu` | Haskell | Format Haskell |

## Custom Hooks

```nix
{
  git-hooks.hooks.unit-tests = {
    enable = true;
    name = "Unit tests";
    entry = "make check";
    files = "\\.(c|h)$";
    types = [ "text" "c" ];
    excludes = [ "irrelevant\\.c" ];
    language = "system";
    pass_filenames = false;
  };
}
```

### Hook Options

| Option | Description |
|--------|-------------|
| `name` | Display name in report |
| `entry` | Command to execute |
| `files` | Regex pattern for files |
| `types` | File types to match |
| `excludes` | Patterns to exclude |
| `language` | How to run (usually "system") |
| `pass_filenames` | Pass changed files to command |

## Package Overrides

```nix
{
  git-hooks.hooks = {
    # Override package version
    ormolu.enable = true;
    ormolu.package = pkgs.haskellPackages.ormolu;

    # Multiple package overrides
    clippy.enable = true;
    clippy.packageOverrides.cargo = pkgs.cargo;
    clippy.packageOverrides.clippy = pkgs.clippy;
    
    # Hook-specific settings
    clippy.settings.allFeatures = true;
  };
}
```

## CI Integration

Run hooks in CI:

```bash
$ devenv test
```

This runs all enabled hooks against the entire codebase.

## Managing .pre-commit-config.yaml

The `.pre-commit-config.yaml` is auto-generated and symlinked. 

- **Don't commit it** - it's in `.gitignore` after `devenv init`
- Changes come from `devenv.nix`, not the yaml file

## Common Patterns

### Python Project

```nix
{
  git-hooks.hooks = {
    black.enable = true;
    ruff.enable = true;
    mypy.enable = true;
  };
}
```

### JavaScript/TypeScript Project

```nix
{
  git-hooks.hooks = {
    eslint.enable = true;
    prettier.enable = true;
  };
}
```

### Rust Project

```nix
{
  git-hooks.hooks = {
    rustfmt.enable = true;
    clippy.enable = true;
  };
}
```

### Multi-language

```nix
{
  git-hooks.hooks = {
    # General
    prettier.enable = true;
    markdownlint.enable = true;
    
    # Nix
    nixfmt.enable = true;
    
    # Shell
    shellcheck.enable = true;
  };
}
```
