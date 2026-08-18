# Zellij Runtime Control Reference

## Contents
- Session lifecycle
- Creating panes & tabs
- Navigation & focus
- Sending input
- Discovering state
- Floating pane management
- Cleanup

## Session Lifecycle

```bash
zellij attach --create-background my-session
zellij attach --create-background my-session options --default-layout /path/to/layout.kdl
zellij list-sessions
zellij --session my-session action new-pane
```

## Creating Panes & Tabs

```bash
zellij action new-pane -- <command>
zellij run --floating --pinned true --width "80%" --height "60%" -- htop
zellij action new-pane --direction right -- tail -f /var/log/syslog
zellij action new-pane --in-place -- htop
zellij action new-pane --stacked
zellij action new-tab --name "build"
zellij action new-tab --name "tests" --layout /path/to/layout.kdl
```

## Navigation & Focus

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

## Sending Input

```bash
zellij action write-chars "ls -la" && zellij action write 10  # newline byte
```

## Discovering State

```bash
zellij action list-clients          # connected clients + pane IDs
zellij action query-tab-names       # tab names only
zellij action dump-screen --full /tmp/out  # viewport/scrollback
zellij action dump-layout           # current layout as KDL
```

## Floating Pane Management

```bash
zellij action toggle-floating-panes                     # toggle visibility
zellij action toggle-pane-pinned                         # focused pane only
zellij action toggle-pane-embed-or-floating --pane-id 3
zellij action change-floating-pane-coordinates --pane-id 1 --x "33%" --y "33%" --width "34%" --height "34%"
```

## Cleanup

```bash
zellij action close-pane    # focused pane
zellij action close-tab     # current tab
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
