# Roles Reference

Roles are defined in `bundles.nix` and group packages and configurations by purpose.

## Available Roles

### base

Essential packages and shell aliases. Always included.

**Packages:** vim, git, gh, devenv, direnv, rclone, bat, jq, tree, watchman, jnv, zinit, fzf, zsh, ripgrep, fd, coreutils, htop, glow, antigen

### developer

Development tools and environment.

**Packages:** emacs, helix, clang, python3, nodejs, yarn, docker, k3d, kubectl, kubernetes-helm, k9s, gh-dash

**Agent Skills:** debugging, tdd, writing-plans, brainstorming, verification-before-completion, receiving-code-review, requesting-code-review, jj

### creative

Media and content creation tools.

**Packages:** ffmpeg, imagemagick, pandoc

**Homebrew Casks (macOS):** elgato-stream-deck

**Agent Skills:** brainstorming, writing-skills, diataxis-docs

### gaming

Gaming tools.

**Packages:** moonlight-qt

### desktop

Desktop applications.

**Packages:** logseq, super-productivity, vivaldi (Linux only)

### workstation

Work-related tools.

**Packages:** slack, trippy, unar

**Agent Skills:** receiving-code-review, requesting-code-review

### entertainment

Entertainment applications.

**Homebrew Casks (macOS):** steam, obs, discord

### agent-skills

AI agent skills management.

**Packages:** git, jq

Automatically enabled by `llm-client` or `llm-claude` roles.

### llm-client

OpenCode with LLM server connection.

**Packages:** opencode

**Agent Skills:** using-superpowers, jj, writing-skills, diataxis-docs

**Enables:** `agent-skills`

### llm-claude

Claude Code integration.

**Packages:** claude-code

**Agent Skills:** using-superpowers, jj, writing-skills, diataxis-docs

**Enables:** `agent-skills`

### llm-host

Local model hosting.

**Packages:** ollama

### llm-server

LiteLLM server (placeholder).

## Role Combinations

Common role combinations:

| Use Case | Roles |
|----------|-------|
| Basic development | `base`, `developer` |
| Full workstation | `base`, `developer`, `workstation`, `llm-client` |
| Creative work | `base`, `creative`, `desktop` |
| Gaming setup | `base`, `entertainment`, `gaming` |

## Platform-Specific Packages

Roles can define platform-specific packages:

- `packages` - All platforms
- `darwinPackages` - macOS only
- `linuxPackages` - Linux only
- `homebrewCasks` - macOS Homebrew casks
