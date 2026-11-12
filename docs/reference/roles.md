# Roles Reference

Roles are defined as NixOS modules in `modules/roles/`. Each role is gated by `myConfig.roles.<name>.enable`.

## Available Roles

### agent-skills

Shell aliases for listing and updating the installed personal skills.

### assistant

### claude

Claude Code AI assistant with rtk token optimization.

**Packages:** claude-code, rtk



### creative

Media and content creation tools.

**Packages:** ffmpeg, imagemagick, pandoc

**Homebrew Casks (macOS):** elgato-stream-deck


### desktop

Desktop applications.

**Packages:** logseq, super-productivity, vivaldi (Linux only)

### developer

Development tools and environment.

**Packages:** emacs, helix, clang, python3, nodejs, yarn, docker, k3d, kubectl, kubernetes-helm, k9s, gh-dash


### developer-packages

### devenv-packages

### email-backup

### entertainment

Entertainment applications.

**Homebrew Casks (macOS):** steam, obs, discord

### foundation

### foundation-packages

### gaming

Gaming tools.

**Packages:** moonlight-qt

### homebrew

### opencode

OpenCode AI assistant with rtk token optimization.

**Packages:** opencode, rtk



### pi

Pi coding agent with rtk token optimization.

**Packages:** pi-coding-agent, rtk


**Enables:** `pi` config management

### tailscale

### work

### workstation

Work-related tools.

**Packages:** slack, trippy, unar


## Role Combinations

Common role combinations:

| Use Case | Roles |
|----------|-------|
| Basic development | `base`, `developer` |
| Full workstation | `base`, `developer`, `workstation`, `opencode` |
| Creative work | `base`, `creative`, `desktop` |
| Gaming setup | `base`, `entertainment`, `gaming` |

## Platform-Specific Packages

Roles can define platform-specific packages:

- `packages` - All platforms
- `darwinPackages` - macOS only
- `linuxPackages` - Linux only
- `homebrewCasks` - macOS Homebrew casks
