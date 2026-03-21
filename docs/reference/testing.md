# Testing

This document describes how to run tests for the Nix system configuration.

## Overview

The test suite validates:
- **Core packages** - Essential packages (git, curl, vim, etc.)
- **Foundation packages** - Development environment packages
- **Options** - Configuration options are properly defined
- **Configuration** - Services and settings are correctly configured

## Running Tests

### Quick Test

Run all tests:
```bash
devenv tasks run test:all
```

### Individual Tests

Run specific test suites:

```bash
# Test core packages
devenv tasks run test:core

# Test foundation packages
devenv tasks run test:foundation

# Test options are defined
devenv tasks run test:options

# Test configuration validation
devenv tasks run test:config
```

### Using Nix Flake Check

Tests are also integrated into `nix flake check`:

```bash
# Run all flake checks (includes tests)
nix flake check

# Run checks for current system only
nix flake check --max-jobs 1
```

### Using devenv Shell

Inside the devenv shell, you can use short aliases:

```bash
# Enter devenv shell
nix develop

# Run tests (aliases defined in devenv.nix)
dt test:all      # Run all tests
dt test:core     # Run core tests
dtq              # Quick check (includes lint)
```

## CI/CD

Tests run automatically in GitHub Actions on every PR:

1. **Foundation Tests** (`test-foundation` job)
   - Core packages test
   - Foundation packages test
   - Options test
   - Configuration validation test

2. **Build Tests** (`build-darwin`, `build-nixos` jobs)
   - Dry-run builds for all configurations

3. **Auxiliary Validation** (`validate-auxiliary` job)
   - Disko configurations
   - Installation script

### CI Test Results

Test results are reported in:
- GitHub Actions logs
- PR status checks
- Build report summary (in PR comments)

## Test Structure

```
tests/
├── default.nix          # Test suite entry point
├── test-options.nix     # Options validation tests
└── test-packages.nix    # Package availability tests
```

### Adding New Tests

To add a new test:

1. Create test logic in an existing file or create a new one
2. Export it from `tests/default.nix`
3. Add it to `flake.nix` checks
4. Add a devenv task to run it

Example:

```nix
# tests/test-example.nix
{ pkgs, ... }: {
  exampleTest = pkgs.runCommand "test-example" {} ''
    echo "Running example test..."
    # Test logic here
    touch $out
  '';
}
```

Then add to `tests/default.nix`:
```nix
example = import ./test-example.nix { inherit pkgs lib self; };
```

And to `flake.nix`:
```nix
checks = forAllSystems (system: let
  # ...
  tests = import ./tests { inherit pkgs self; inherit (nixpkgs) lib; };
in {
  inherit (tests) foundation-options core-packages foundation-packages config-validation example;
});
```

## Troubleshooting

### Tests Fail with "attribute not found"

Ensure the test is properly exported in `tests/default.nix` and included in `flake.nix` checks.

### Tests Timeout

Some tests build packages which can take time. Use `--max-jobs` to limit parallelism:
```bash
nix flake check --max-jobs 2
```

### Local Testing Without CI

To test the same checks that run in CI:
```bash
# Run all checks
nix flake check

# Or use devenv for more control
devenv tasks run check:lint
devenv tasks run test:all
```

## Test Coverage

Current test coverage:

| Component | Test File | CI Job |
|-----------|-----------|--------|
| Core packages | `test-packages.nix` | test-foundation |
| Foundation packages | `test-packages.nix` | test-foundation |
| Options | `test-options.nix` | test-foundation |
| Configuration | `test-packages.nix` | test-foundation |
| Disko configs | devenv task | validate-auxiliary |
| Install script | devenv task | validate-auxiliary |
| Darwin builds | devenv task | build-darwin |
| NixOS builds | devenv task | build-nixos |

## Future Improvements

Planned test additions:
- NixOS VM integration tests
- 1Password SSH agent functional tests
- Sudo authentication tests
- Fresh bootstrap validation
