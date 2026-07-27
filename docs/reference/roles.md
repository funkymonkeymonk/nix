# Roles Reference

Roles are defined as NixOS/Darwin modules in `modules/roles/`. Most roles are gated by `myConfig.roles.<name>.enable`. Two exceptions: `tailscale` is gated by its own `myConfig.tailscale.enable` (not nested under `roles`), and `foundation-packages.nix` is a plain package-list data file consumed by `foundation.nix`, not an independently-gated role.

## Available Roles

### agent-skills

AI agent skills management (shell aliases and env vars for inspecting installed skills). Auto-enabled by the `opencode`, `claude`, and `pi` roles.

> **Known issue:** this module's own `mkIf` gate currently reads a different option path (`myConfig.roles.agent-skills.enable`) than the one `opencode`/`claude`/`pi` roles actually set (`myConfig.agent-skills.enable`), so its shell aliases don't currently activate. Tracked separately in the yak backlog.

### assistant

Agent-facing email tools with direct Gmail access (as opposed to `email-backup`'s read-only archival pipeline).

**Packages:** himalaya, gmailctl

**Enables:** `myConfig.email-agent.enable`

### claude

Claude Code AI assistant with rtk token optimization.

**Packages:** claude-code, rtk

**Agent Skills:** using-superpowers, jj, writing-skills, diataxis-docs, ralph-specs, prd-review

**Enables:** `agent-skills`

### creative

Media and content creation tools.

**Packages:** ffmpeg, imagemagick, pandoc

**Homebrew Casks (macOS):** elgato-stream-deck

**Agent Skills:** brainstorming, writing-skills, diataxis-docs

### desktop

Desktop applications.

**Packages:** logseq, super-productivity, vivaldi (Linux only)

### developer

Development tools and environment.

**Packages:** emacs, helix, clang, python3, nodejs, yarn, docker, k3d, kubectl, kubernetes-helm, k9s, gh-dash

**Agent Skills:** debugging, tdd, writing-plans, brainstorming, verification-before-completion, receiving-code-review, requesting-code-review, jj

### email-backup

Immutable, encrypted, searchable email backups (pull-only mbsync → notmuch index → restic snapshots). Distinct from `assistant`, which gives agents live Gmail access.

**Packages:** isync, notmuch, restic

**Enables:** `myConfig.email-backup.enable`

### entertainment

Entertainment applications.

**Homebrew Casks (macOS):** steam, obs, discord

### foundation

Essential base tools, enabled by default on every machine (`enable` defaults to `true`).

**Packages:** 1Password CLI, git, jujutsu, delta, helix, zsh, htop, zellij, yazi, and other always-on utilities (see `modules/roles/foundation-packages.nix`)

### gaming

Gaming tools.

**Packages:** moonlight-qt

### homebrew

Enables `nix-homebrew` integration and Homebrew auto-migration on Darwin. Only import this for systems that actually have Homebrew installed — it's not imported by default the way other roles are (see the note in `modules/common/users.nix`).

### llm-host

Local model hosting.

**Packages:** ollama

### opencode

OpenCode AI assistant with rtk token optimization.

**Packages:** opencode, rtk

**Agent Skills:** using-superpowers, jj, writing-skills, diataxis-docs, ralph-specs, prd-review

**Enables:** `agent-skills`

### pi

Pi coding agent with rtk token optimization.

**Packages:** pi-coding-agent, rtk

**Agent Skills:** using-superpowers, jj, writing-skills, diataxis-docs, ralph-specs, prd-review

**Enables:** `agent-skills`, `pi` config management

### tailscale

Tailscale VPN with auto-connect via 1Password secrets. Unlike other roles, this is gated by `myConfig.tailscale.enable` directly (not `myConfig.roles.tailscale.enable`).

**Packages:** tailscale

### workstation

Work-related tools.

**Packages:** slack, trippy, unar

**Agent Skills:** receiving-code-review, requesting-code-review

## Role Combinations

Common role combinations:

| Use Case | Roles |
|----------|-------|
| Basic development | `foundation`, `developer` |
| Full workstation | `foundation`, `developer`, `workstation`, `opencode` |
| Creative work | `foundation`, `creative`, `desktop` |
| Gaming setup | `foundation`, `entertainment`, `gaming` |

`foundation` is always enabled by default — it's listed here for clarity, not because you need to enable it explicitly.

## Platform-Specific Packages

Roles can define platform-specific packages:

- `packages` - All platforms
- `darwinPackages` - macOS only
- `linuxPackages` - Linux only
- `homebrewCasks` - macOS Homebrew casks
