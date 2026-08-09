# Devenv Packages

Add executables and libraries to your development environment.

## Quick Reference

```bash
# Search for packages
devenv search <name>

# In devenv.nix
packages = [ pkgs.git pkgs.jq ];
```

## Adding Packages

```nix
{ pkgs, ... }:

{
  packages = [
    # Executables
    pkgs.git
    pkgs.jq
    pkgs.curl
    pkgs.ripgrep
    
    # Libraries
    pkgs.libffi
    pkgs.zlib
    pkgs.openssl
  ];
}
```

Packages are added to PATH when you enter the shell:

```bash
$ jq
jq: command not found

$ devenv shell
(devenv) $ jq --version
jq-1.6
```

## Searching Packages

```bash
$ devenv search ncdu
name         version  description
----         -------  -----------
pkgs.ncdu    2.2.1    Disk usage analyzer with an ncurses interface
pkgs.ncdu_1  1.17     Disk usage analyzer with an ncurses interface
pkgs.ncdu_2  2.2.1    Disk usage analyzer with an ncurses interface
```

Searches nixpkgs pinned in your `devenv.lock`.

## Finding Package by File

Find which package provides a specific file:

```bash
$ nix run github:nix-community/nix-index-database libquadmath.so
```

## Package Versions

For different versions, use nixpkgs overlays or fetch from another input:

```nix
# In devenv.yaml, add another nixpkgs input
inputs:
  nixpkgs-stable:
    url: github:NixOS/nixpkgs/nixos-23.11

# In devenv.nix
{ pkgs, inputs, ... }:

let
  pkgs-stable = import inputs.nixpkgs-stable { system = pkgs.system; };
in {
  packages = [
    pkgs.nodejs_20        # From default nixpkgs
    pkgs-stable.nodejs_18 # From stable nixpkgs
  ];
}
```

## Language-Specific Packages

Many languages have their own package options:

```nix
{
  # Python packages
  languages.python = {
    enable = true;
    package = pkgs.python311;
    venv.enable = true;
  };

  # Node packages via npm/yarn
  languages.javascript = {
    enable = true;
    npm.install.enable = true;
  };

  # Rust with cargo
  languages.rust.enable = true;
}
```

## Conditional Packages

```nix
{ pkgs, lib, ... }:

{
  packages = [
    pkgs.git
  ] ++ lib.optionals pkgs.stdenv.isLinux [
    pkgs.strace
  ] ++ lib.optionals pkgs.stdenv.isDarwin [
    pkgs.darwin.apple_sdk.frameworks.Security
  ];
}
```

## Package Attributes

Find available attributes:

```bash
# In nix repl
$ nix repl
nix-repl> :lf .
nix-repl> devenv.packages.x86_64-linux.<TAB>
```

Or browse https://search.nixos.org/packages
