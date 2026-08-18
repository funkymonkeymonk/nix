---
name: zellij
description: Zellij terminal multiplexer — creating KDL layouts, managing sessions via CLI, and running commands without disrupting the user's workspace
---

# Zellij

## Overview

Zellij is a terminal multiplexer. Layouts (KDL files) define pane/tab arrangement at startup. The `zellij action` CLI controls running sessions.

**Full KDL syntax**: [references/kdl-syntax.md](references/kdl-syntax.md)
**Full runtime command reference**: [references/runtime-commands.md](references/runtime-commands.md)

## Decision Flow: Running Commands Without Disruption

Never type in the user's active pane. Never steal focus. Always create dedicated panes/tabs, then return focus immediately.

```
                    ┌──────────────────────┐
                    │ Need to run a command │
                    └──────────┬───────────┘
                               │
                    ┌──────────▼───────────┐
                    │ Fits in 1-2 lines?   │
                    └──────┬───────┬───────┘
                       no  │       │  yes
                    ┌──────▼───┐   ▼
                    │          │ Report inline
                    │ ┌───────▼────────┐
                    │ │ Interactive?   │
                    │ │ (htop, less..) │
                    │ └──┬──────┬─────┘
                    │ yes│      │ no
                    │  ┌─▼──┐  │
                    │  │    │  │
                    │  │    ┌──▼──────────────────────┐
                    │  │    │ Long-running (>30s) or   │
                    │  │    │ needs background?        │
                    │  │    └──┬───────────┬──────────┘
                    │  │   yes │           │ no
                    │  │ ┌────▼───┐  ┌────▼────┐
                    │  │ │        │  │         │
                    │  │ │  New   │  │ Floating│
                    │  │ │  Tab   │  │  Pane   │
                    │  │ │        │  │         │
                    │  │ └───┬────┘  └──┬──────┘
                    │  └──┬───┘         │
                    │     │             │
                    └─────┴──────┬──────┘
                                 │
                                 ▼
                    ┌────────────────────────┐
                    │ MUST restore focus:     │
                    │ focus-previous-pane or  │
                    │ go-to-tab <original>    │
                    └────────────────────────┘
```

### Patterns

**Floating pane** (temporary output, interactive tools):
```bash
zellij run --floating --pinned true --width "80%" --height "60%" -- htop
zellij action focus-previous-pane
```
- `--pinned true` keeps it on top. `--close-on-exit` (`-c`) auto-dismisses.
- Interactive tools: `--width "90%" --height "90%"`. Quick output: `--width "60%" --height "40%" -c`.

**New tab** (long-running processes, builds):
```bash
zellij action new-tab --name "build-$(date +%s)"
sleep 1  # shell needs init time
zellij action write-chars "cargo build"
zellij action write 10
zellij action go-to-tab 0  # restore user's tab
```

**Split pane** (visible alongside user's work):
```bash
zellij action new-pane --direction right -- <command>
zellij action focus-previous-pane
```

## Focus Management (CRITICAL)

**Never leave the user in a different pane or tab than where they started.**

After every pane/tab creation:
- **Floating/split pane**: `zellij action focus-previous-pane`
- **New tab**: `zellij action go-to-tab <original-index>` (use floating pane if index unknown)

Exception: only when the user explicitly asks to switch.

## Common Mistakes

| Symptom | Fix |
|---------|------|
| Pane on wrong side | `split_direction`: `"horizontal"` = stacked T/B, `"vertical"` = side-by-side |
| Used `split_direction="stacked"` | Use `stacked=true` on parent pane |
| Floating pane hidden behind others | Missing `--pinned true` |
| Command lost in new tab | Add `sleep 1` after `new-tab` (shell needs init) |
| Focus not restored | Always call `focus-previous-pane` or `go-to-tab` |
| Decimal percentages fail | Use integers: `"33%"` not `"33.33%"` |
| Template children missing | Missing `children` placeholder in template |
| `args` on same line as pane | Must be in child-braces |
| All tabs look the same | No `tab` nodes → layout is one big default_tab_template |
| Used `paste` / `send-keys` | Doesn't exist in 0.43.1; use `write-chars` + `write 10` |
| Used `--layout-string` | Not available; use `--layout <file>` |
| Pane with children no split_direction | Layout renders incorrectly; add `split_direction` |

## Quick Reference

```bash
# Layouts
zellij --layout file.kdl
zellij action new-tab --name "work" --layout file.kdl

# Floating pane + restore focus
zellij run --floating --pinned true -c --width "60%" --height "40%" -- <cmd>
zellij action focus-previous-pane

# Tab for long process
zellij action new-tab --name "task"
sleep 1 && zellij action write-chars "<cmd>" && zellij action write 10
zellij action go-to-tab 0

# Send text
zellij action write-chars "echo hi" && zellij action write 10

# Navigate
zellij action go-to-tab-name "build"
zellij action focus-previous-pane

# Discover
zellij action list-clients
zellij action dump-layout

# Cleanup
zellij action close-pane
zellij action close-tab
zellij action toggle-floating-panes
```
