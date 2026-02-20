---
name: zellij
description: Manage Zellij terminal multiplexer. Create panes, tabs, run commands, and control the terminal workspace from within OpenCode.
---

# Zellij Terminal Multiplexer

## Overview

Zellij is a terminal workspace with batteries included. This skill enables OpenCode to manage the terminal multiplexer it runs in - creating panes, tabs, running commands in new panes, and organizing the workspace.

## Key Concepts

- **Panes**: Individual terminal instances within a tab
- **Tabs**: Groups of panes (like browser tabs)
- **Floating Panes**: Overlay panes that float above others
- **Sessions**: Named Zellij instances you can attach/detach

## Environment Detection

Check if running inside Zellij:

```bash
# ZELLIJ env var is set when inside a session
if [ -n "$ZELLIJ" ]; then
  echo "Inside Zellij session"
fi

# Get current pane ID
echo $ZELLIJ_PANE_ID

# Get current session name (from ZELLIJ_SESSION_NAME env var)
echo $ZELLIJ_SESSION_NAME
```

## Session Identification

**IMPORTANT**: When OpenCode runs commands via Bash, they execute in a sandboxed environment that does NOT inherit the `$ZELLIJ` or `$ZELLIJ_SESSION_NAME` environment variables. This means `zellij action` commands won't automatically target the current session.

### Identifying the Current Session

Since environment variables aren't available in the sandbox, use these strategies:

1. **Ask the user** - If session identity matters, ask which session they're in
2. **List and filter sessions** - Use `zellij list-sessions` to find active sessions
3. **Use naming conventions** - Sessions named with repo/branch info are easier to identify

```bash
# List all sessions (active ones don't show EXITED)
zellij list-sessions

# Filter to only active sessions
zellij list-sessions | grep -v EXITED

# Find sessions by pattern (e.g., repo name)
zellij list-sessions | grep "nix"
```

### Targeting a Specific Session

To run actions on a specific session (not the current one), use the `-s` flag BEFORE the `action` subcommand:

```bash
# Target a specific session with -s flag
zellij -s <session-name> action <command>

# Example: rename a specific session
zellij -s old-session-name action rename-session new-session-name

# Example: create pane in specific session
zellij -s my-session action new-pane -d right
```

### Renaming Sessions

```bash
# Rename the current session (only works from inside that session)
zellij action rename-session "new-name"

# Rename a specific session from outside (use -s flag)
zellij -s current-session-name action rename-session new-session-name
```

### Recommended Session Naming Convention

For environments with many parallel sessions, use a structured naming scheme:

```
<repo>-<branch-or-bookmark>-<short-guid>
```

Example workflow:
```bash
# Get repo name from directory
repo=$(basename $(pwd))

# Get branch/bookmark (git or jj)
branch=$(git branch --show-current 2>/dev/null || jj log -r @ --no-graph -T 'bookmarks' 2>/dev/null | head -1)

# Generate short unique ID
guid=$(uuidgen | cut -c1-8 | tr '[:upper:]' '[:lower:]')

# Compose session name
session_name="${repo}-${branch}-${guid}"

# Rename session (targeting it explicitly)
zellij -s <old-session-name> action rename-session "$session_name"
```

This produces names like: `nix-push-yustvyxxqvyy-0e314b2d`

## Core Commands

### Creating Panes

```bash
# New pane in best available space
zellij action new-pane

# New pane in specific direction
zellij action new-pane -d right    # right, left, up, down
zellij action new-pane -d down

# New floating pane
zellij action new-pane -f

# New pane with specific name
zellij action new-pane -n "my-pane"

# New pane with specific working directory
zellij action new-pane --cwd /path/to/dir
```

### Running Commands in New Panes

The `zellij run` command (or `zellij action new-pane -- <cmd>`) creates panes that:
- Show exit status on completion
- Allow re-running with ENTER
- Close with Ctrl-C

```bash
# Run command in new pane
zellij run -- git diff

# Run in floating pane
zellij run -f -- htop

# Run and close on exit
zellij run -c -- ls -la

# Run in specific direction
zellij run -d right -- tail -f /var/log/syslog

# Run with custom name
zellij run -n "logs" -- tail -f app.log

# Run in-place (suspend current pane temporarily)
zellij run -i -- vim file.txt

# Start suspended (wait for ENTER before running)
zellij run -s -- make build
```

### Editing Files

```bash
# Open file in new pane with $EDITOR
zellij edit ./file.rs

# Open in floating pane
zellij edit -f ./file.rs

# Open at specific line
zellij edit -l 42 ./file.rs

# Open in specific direction
zellij edit -d right ./file.rs
```

### Managing Tabs

```bash
# Create new tab
zellij action new-tab

# Create tab with name
zellij action new-tab -n "build"

# Create tab with layout
zellij action new-tab -l compact

# Navigate tabs
zellij action go-to-tab 1              # By index (1-based)
zellij action go-to-tab-name "build"   # By name
zellij action go-to-next-tab
zellij action go-to-previous-tab

# Rename current tab
zellij action rename-tab "new-name"

# Close current tab
zellij action close-tab

# Query tab names
zellij action query-tab-names
```

### Pane Navigation and Focus

```bash
# Move focus
zellij action move-focus left    # left, right, up, down
zellij action move-focus right

# Focus next/previous pane
zellij action focus-next-pane
zellij action focus-previous-pane

# Move pane location
zellij action move-pane left     # left, right, up, down
```

### Floating Panes

```bash
# Toggle floating panes visibility
zellij action toggle-floating-panes

# Toggle current pane between embedded/floating
zellij action toggle-pane-embed-or-floating

# Pin floating pane (always on top)
zellij action toggle-pane-pinned

# Change floating pane coordinates
zellij action change-floating-pane-coordinates \
  --pane-id terminal_1 \
  --width 50% --height 50% \
  -x 25% -y 25%
```

### Pane Management

```bash
# Close focused pane
zellij action close-pane

# Rename focused pane
zellij action rename-pane "my-pane-name"
zellij action undo-rename-pane

# Toggle fullscreen
zellij action toggle-fullscreen

# Resize pane
zellij action resize left     # left, right, up, down
zellij action resize +        # increase size
zellij action resize -        # decrease size

# Toggle pane frames
zellij action toggle-pane-frames
```

### Scrollback and Content

```bash
# Dump pane scrollback to file
zellij action dump-screen /tmp/screen.txt

# Edit scrollback in $EDITOR
zellij action edit-scrollback

# Scroll commands
zellij action scroll-up
zellij action scroll-down
zellij action page-scroll-up
zellij action page-scroll-down
zellij action half-page-scroll-up
zellij action half-page-scroll-down
zellij action scroll-to-bottom
```

### Writing to Panes

```bash
# Write characters to focused pane
zellij action write-chars "Hello, World!"

# Write bytes
zellij action write 72 101 108 108 111   # "Hello"
```

### Session Management

```bash
# List sessions
zellij list-sessions
zellij ls

# List only active sessions (filter out EXITED)
zellij list-sessions | grep -v EXITED

# Attach to session
zellij attach my-session
zellij a my-session

# Kill session
zellij kill-session my-session
zellij k my-session

# Kill all sessions
zellij kill-all-sessions
zellij ka

# Delete a specific session (removes from list)
zellij delete-session my-session
zellij d my-session

# Delete all sessions
zellij delete-all-sessions
zellij da

# Dump current layout
zellij action dump-layout

# Rename session (from inside that session)
zellij action rename-session "new-name"

# Rename session (targeting specific session from outside)
zellij -s old-name action rename-session new-name
```

### Mode Switching

```bash
# Switch input mode
zellij action switch-mode locked    # locked, pane, tab, resize, move, search, session, tmux
zellij action switch-mode pane
```

### Sync and Clients

```bash
# Toggle sync mode (send input to all panes in tab)
zellij action toggle-active-sync-tab

# List connected clients
zellij action list-clients
```

## Common Patterns for OpenCode

### Run Tests in Side Pane

```bash
# Create a test runner pane to the right
zellij run -d right -n "tests" -- npm test
```

### Open Build Output

```bash
# Floating pane for build output
zellij run -f -n "build" -- make build
```

### Create Development Layout

```bash
# Main editor stays focused, create helper panes
zellij action new-pane -d down -n "terminal"
zellij action new-pane -d right -n "logs"
```

### Quick File Preview

```bash
# Floating pane to preview a file
zellij run -f -c -- cat README.md
```

### Run Long-Running Processes

```bash
# Start server in named pane
zellij run -d down -n "server" -- npm run dev
```

### Capture Output for Analysis

```bash
# Dump screen content then analyze
zellij action dump-screen /tmp/output.txt
cat /tmp/output.txt
```

## Best Practices

1. **Name your panes** - Use `-n` flag for easy identification
2. **Use floating for quick tasks** - `-f` flag for temporary work
3. **Use in-place for editing** - `-i` flag to replace current pane temporarily
4. **Close on exit for one-shots** - `-c` flag for commands you just want to see once
5. **Check ZELLIJ env var** - Ensure commands only run inside Zellij

## Tips for AI Agents

### Critical: Sandbox Limitations

OpenCode's Bash tool runs in a sandboxed environment that does NOT have access to Zellij environment variables (`$ZELLIJ`, `$ZELLIJ_SESSION_NAME`, `$ZELLIJ_PANE_ID`). This means:

1. **`zellij action` commands won't work directly** - They require being "inside" a session
2. **You must target sessions explicitly** - Use `zellij -s <session-name> action <command>`
3. **You cannot detect the current session automatically** - Ask the user or use heuristics

### Session Identification Strategies

When you need to know which session you're in:

1. **Ask the user directly** - "What is your current zellij session name?"
2. **List and narrow down** - Use `zellij list-sessions | grep -v EXITED` to find active sessions
3. **Use context clues** - If only one active session exists, that's likely it
4. **Check recent sessions** - The most recently created active session is often the current one

### General Best Practices

- Always check if inside Zellij before issuing commands
- Use `zellij run` instead of `zellij action new-pane -- cmd` for cleaner syntax
- Name panes descriptively so you can reference them later
- Use floating panes for output that needs temporary attention
- Use `dump-screen` to capture pane output for analysis
- Consider using `--close-on-exit` for commands where you just need the result
- When renaming sessions, use the pattern: `<repo>-<branch>-<short-guid>`
- Always use `-s <session>` flag when targeting a specific session from sandbox
