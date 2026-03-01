# Roles Reference

Roles are defined in `bundles.nix` and group packages and configurations by purpose.

## Available Roles

### base

Essential packages and shell configuration. Always included.

**Packages:** vim, git, gh, devenv, direnv, rclone, bat, jq, tree, watchman, jnv, zinit, fzf, zsh, ripgrep, fd, coreutils, htop, glow, antigen

**Config:** Shell aliases, environment variables, zsh enabled

### developer

Development tools and environment.

**Packages:** emacs, helix, clang, python3, nodejs, yarn, docker, k3d, kubectl, kubernetes-helm, k9s, gh-dash

**Agent Skills:** debugging, tdd, writing-plans, brainstorming, verification-before-completion, receiving-code-review, requesting-code-review, jj, diataxis-docs, ralph-specs, prd-review, writing-skills

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

**Packages:** logseq, super-productivity

**Linux only:** vivaldi

### workstation

Work-related tools.

**Packages:** slack, trippy, unar

**Agent Skills:** receiving-code-review, requesting-code-review

### entertainment

Entertainment applications (macOS only).

**Homebrew Casks:** steam, obs, discord

### agent-skills

AI agent skills management. Auto-enabled by `llm-client` or `llm-claude`.

**Config:** Session variables (`AGENT_SKILLS_PATH`, `SUPERPOWERS_SKILLS_PATH`), shell aliases (`skills-status`, `skills-update`, `skills-list`)

### llm-client

OpenCode with LLM server connection.

**Packages:** opencode, rtk

**Agent Skills:** using-superpowers, jj, writing-skills, diataxis-docs, ralph-specs, prd-review

**Enables:** `agent-skills`

### llm-claude

Claude Code integration.

**Packages:** claude-code

**Agent Skills:** using-superpowers, jj, writing-skills, diataxis-docs, ralph-specs, prd-review

**Enables:** `agent-skills`

### llm-host

Local model hosting.

**Packages:** ollama

### llm-server

LiteLLM server (placeholder).

## Platform-Specific

### darwin (macOS)

**Packages:** google-chrome, hidden-bar, goose-cli, claude-code, alacritty-theme, colima, home-manager

**Homebrew Casks:** raycast, zed, zen, ghostty, deezer, block-goose, sensei, vivaldi, 1password

## Role Combinations

| Use Case | Roles |
|----------|-------|
| Basic development | `developer` |
| Full workstation | `developer`, `workstation`, `llm-client` |
| Creative work | `creative`, `desktop` |
| Gaming setup | `entertainment`, `gaming` |

## Role Attributes

| Attribute | Platform | Description |
|-----------|----------|-------------|
| `packages` | All | Nix packages |
| `homebrewCasks` | macOS | Homebrew cask apps |
| `enableAgentSkills` | All | Auto-enable agent-skills role |
| `config` | All | Environment variables, aliases |
