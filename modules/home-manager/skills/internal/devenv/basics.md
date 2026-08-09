# Devenv Basics

Installation, setup, updating, and direnv integration.

## Installation

### 1. Install Nix

**Linux:**
```bash
sh <(curl -L https://nixos.org/nix/install) --daemon
```

**macOS:**
```bash
curl -sSfL https://artifacts.nixos.org/nix-installer | sh -s -- install
```

**macOS Bash upgrade** (recommended):
```bash
nix-env --install --attr bashInteractive -f https://github.com/NixOS/nixpkgs/tarball/nixpkgs-unstable
```

### 2. Install devenv

```bash
nix-env --install --attr devenv -f https://github.com/NixOS/nixpkgs/tarball/nixpkgs-unstable
```

### 3. Configure GitHub Token (Optional)

Avoid rate limiting by adding to `~/.config/nix/nix.conf`:
```
access-tokens = github.com=<GITHUB_TOKEN>
```

Create token at: https://github.com/settings/personal-access-tokens/new

## Project Setup

```bash
$ devenv init
• Creating devenv.nix
• Creating devenv.yaml
• Creating .gitignore
```

## Commands

| Command | Purpose |
|---------|---------|
| `devenv shell` | Enter development environment |
| `devenv up` | Start processes |
| `devenv test` | Run tests and checks |
| `devenv search <name>` | Search packages |
| `devenv update` | Update inputs in devenv.lock |
| `devenv gc` | Garbage collect old environments |
| `devenv info` | Show environment info |

## Updating

### Update devenv CLI

```bash
nix-env --upgrade --attr devenv -f https://github.com/NixOS/nixpkgs/tarball/nixpkgs-unstable
```

### Update Project Inputs

```bash
devenv update
```

This updates `devenv.lock` with latest versions from `devenv.yaml` inputs.

## direnv Integration

Auto-activate devenv when entering project directory.

### 1. Install direnv

**macOS:**
```bash
brew install direnv
```

**Linux:**
```bash
# Ubuntu/Debian
sudo apt install direnv

# Or via nix
nix-env -iA nixpkgs.direnv
```

### 2. Add Shell Hook

**Bash** (`~/.bashrc`):
```bash
eval "$(direnv hook bash)"
```

**Zsh** (`~/.zshrc`):
```bash
eval "$(direnv hook zsh)"
```

**Fish** (`~/.config/fish/config.fish`):
```fish
direnv hook fish | source
```

### 3. Create .envrc

In your project:

```bash
#!/usr/bin/env bash

eval "$(devenv direnvrc)"

# Optional: pass flags
# use devenv --impure --option services.postgres.enable:bool true
use devenv
```

### 4. Allow direnv

```bash
direnv allow
```

Now shell activates automatically on `cd`:

```bash
$ cd ~/myproject/
direnv: loading ~/myproject/.envrc
Building shell ...
Entering shell ...

(devenv) $
```

### Customizing PS1

Install [Starship](https://starship.rs/guide/) for devenv-aware prompt.

### Ignoring .direnv

Add to `.gitignore` (done by `devenv init`):
```
.direnv
```

## Useful Flags

| Flag | Purpose |
|------|---------|
| `--impure` | Allow impure operations |
| `--verbose` | Detailed output |
| `--refresh-eval-cache` | Force re-evaluation |
| `--no-tui` | Disable interactive UI |
| `-P, --profile <name>` | Use specific profile |

## Environment Variables

```bash
$DEVENV_ROOT      # Project root
$DEVENV_DOTFILE   # .devenv directory
$DEVENV_STATE     # Persistent state
$DEVENV_RUNTIME   # Runtime files
$DEVENV_PROFILE   # Nix store profile path
```
