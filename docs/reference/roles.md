# Roles Reference

Roles are defined as NixOS modules in `modules/roles/`. Each role is gated by `myConfig.roles.<name>.enable`.

## Available Roles

### agent-skills

AI agent skills management.

**Packages:** git, jq

Automatically enabled by `opencode` or `claude` roles.

### assistant

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

### entertainment

Entertainment applications.

**Homebrew Casks (macOS):** steam, obs, discord

### foundation

### gaming

Gaming tools.

**Packages:** moonlight-qt

### homebrew

### llm-host

Local model hosting.

**Packages:** vllm-mlx (installed via uv)

### microvm-host

### openclaw-server

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

### workstation

Work-related tools.

**Packages:** slack, trippy, unar

**Agent Skills:** receiving-code-review, requesting-code-review

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
