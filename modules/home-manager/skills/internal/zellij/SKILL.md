---
name: zellij
description: Zellij terminal multiplexer — creating KDL layouts, managing sessions via CLI, and running commands without disrupting the user's workspace
---

# Zellij

## Overview

Zellij is a terminal multiplexer. Layouts (KDL files) define pane/tab arrangement at startup. The `zellij action` CLI controls running sessions.

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

## Layout Authoring (KDL)

Applied at startup (`zellij --layout file.kdl`) or on new tabs (`zellij action new-tab --layout file.kdl`).

### Structure

```
layout {
    pane | tab | pane_template | tab_template | default_tab_template | new_tab_template
}
```

No `tab` nodes → entire content becomes `default_tab_template`.

### Pane Attributes

Child-braces for `args`, same-line otherwise:

| Attribute | Values | Notes |
|-----------|--------|-------|
| `split_direction` | `"horizontal"` / `"vertical"` | `"horizontal"` → stacked T/B; `"vertical"` → side-by-side L/R |
| `size` | `"50%"` / integer | Fixed or percentage space |
| `command` | path | Runs instead of shell |
| `args` | quoted strings | Child-braces: `{ args "-f" "/tmp/log" }` |
| `cwd` | path | Relative composes with parent |
| `focus` | `true` | First focused pane wins |
| `borderless` | `true` | Removes frame |
| `close_on_exit` | `true` | Closes when command exits |
| `start_suspended` | `true` | Waits for Enter |
| `stacked` | `true` | Children stack (one visible) |

```kdl
layout {
    pane command="htop"
    pane { command "htop"; args "-f" "/tmp/log" }
    pane { plugin location="zellij:status-bar" }
    pane { plugin location="file:/path/to/plugin.wasm" }
}
```

### Floating Panes

```kdl
floating_panes {
    pane { x 1 y "10%" width 200 height "50%" }
}
```

`x`, `y`, `width`, `height`: integer chars or quoted percentages.

### Tabs

```kdl
tab name="editor" focus=true split_direction="vertical" {
    pane; pane
}
tab name="logs" cwd="/var/log" {
    pane command="tail" { args "-f" "syslog" }
}
tab hide_floating_panes=true { pane; floating_panes { pane } }
```

Tab attributes: `name`, `split_direction`, `focus`, `cwd`, `hide_floating_panes`.

### Templates

```kdl
pane_template name="htop" command="htop"
pane_template name="stack" split_direction="vertical" {
    pane; children; pane  # insertion point
}
htop                            # use by bare name
stack { pane command="htop" }

tab_template name="with-bar" {
    pane borderless=true { plugin location="zellij:compact-bar" }
    children
}
with-bar name="tab 1" { pane }

default_tab_template { ... }    # all tabs
new_tab_template { ... }        # only runtime new tabs
```

## Layout Testing

Parse-check a layout without affecting the running session:

```bash
zellij --layout path/to/layout.kdl 2>&1
```

**Must run outside a Zellij session.** Inside a session, `zellij --layout` opens a new tab instead of testing.

Reading the output:
- `Failed to parse Zellij configuration` at line N — real parse error
- `could not enable raw mode: Os { code: 6, ... }` — **layout is valid** (the raw-mode error is from running without a TTY)

### Verification Flow

```
Edit layout
  → Parse-check outside session: zellij --layout file.kdl 2>&1
  → "Failed to parse"? → fix reported line, re-test
  → Only raw-mode error? → layout is valid
  → Apply: zellij action new-tab --layout file.kdl (runtime test)
  → Present to user
```

## Runtime Control

### Session Lifecycle

```bash
zellij attach --create-background my-session
zellij attach --create-background my-session options --default-layout /path/to/layout.kdl
zellij list-sessions
zellij --session my-session action new-pane
```

### Creating Panes & Tabs

```bash
zellij action new-pane -- <command>
zellij run --floating --pinned true --width "80%" --height "60%" -- htop
zellij action new-pane --direction right -- tail -f /var/log/syslog
zellij action new-pane --in-place -- htop
zellij action new-pane --stacked
zellij action new-tab --name "build"
zellij action new-tab --name "tests" --layout /path/to/layout.kdl
```

### Navigation & Focus

```bash
zellij action go-to-tab 0
zellij action go-to-tab-name "build"
zellij action go-to-tab-name --create "build"
zellij action go-to-next-tab
zellij action focus-next-pane
zellij action focus-previous-pane
zellij action move-focus right
zellij action move-focus-or-tab down
```

### Sending Input

```bash
zellij action write-chars "ls -la" && zellij action write 10  # newline byte
```

### Discovering State

```bash
zellij action list-clients          # connected clients + pane IDs
zellij action query-tab-names       # tab names only
zellij action dump-screen --full /tmp/out  # viewport/scrollback
zellij action dump-layout           # current layout as KDL
```

### Floating Pane Management

```bash
zellij action toggle-floating-panes                     # toggle visibility
zellij action toggle-pane-pinned                         # focused pane only
zellij action toggle-pane-embed-or-floating --pane-id 3
zellij action change-floating-pane-coordinates --pane-id 1 --x "33%" --y "33%" --width "34%" --height "34%"
```

### Cleanup

```bash
zellij action close-pane    # focused pane
zellij action close-tab     # current tab
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
